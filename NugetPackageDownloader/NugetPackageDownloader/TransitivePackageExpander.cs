using System.IO.Compression;
using System.Xml.Linq;

using Microsoft.Extensions.Configuration;

namespace NugetPackageDownloader;

public sealed class TransitivePackageExpander
{
	private readonly IConfigurationRoot _configuration;
	private readonly bool _enabled;
	private bool _searchExpanded;
	private bool _searchNupkg;
	private readonly string _dataFileName;
	private readonly string _missingFileName;
	private readonly IReadOnlyList<string> _expandedFolders;
	private readonly IReadOnlyList<string> _nupkgFolders;

	public TransitivePackageExpander(Microsoft.Extensions.Configuration.IConfigurationRoot configuration)
	{
		_configuration = configuration;
		_enabled = Convert.ToBoolean(_configuration["TransitivePackages:Enabled"]);
		_searchExpanded = Convert.ToBoolean(_configuration["TransitivePackages:SearchExpandedFolders"]);
		_searchNupkg = Convert.ToBoolean(_configuration["TransitivePackages:SearchNupkgFolders"]);
		_dataFileName = ResolveDataFile(_configuration["Globals:DataFile"], _configuration["Globals:DataFileName"] ?? "");
		_missingFileName = ResolveDataFile(_configuration["Globals:DataFile"], _configuration["Globals:MissingFileName"] ?? "");
		_expandedFolders = _configuration.GetSection("Globals:ExpandedFolders").GetChildren().Select(x => ResolvePath(x.Value!)).ToList() ?? [];
		_nupkgFolders = _configuration.GetSection("Globals:NupkgFolders").GetChildren().Select(x => ResolvePath(x.Value!)).ToList() ?? [];
	}

	private string ResolvePath(string path)
	{
		return path.Replace("%USERPROFILE%", Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
	}

	public void Run()
	{
		if (!_enabled)
		{
			Console.WriteLine("TransitivePackages.Enabled = false. Expander will not run.");
			return;
		}

		if (!File.Exists(_dataFileName))
		{
			Console.WriteLine($"Input file not found: {_dataFileName}");
			return;
		}

		if (!_searchExpanded && !_searchNupkg)
		{
			Console.WriteLine("Both SearchExpandedFolders and SearchNupkgFolders are disabled. No dependencies can be resolved.");
			return;
		}

		var initial = LoadCsv(_dataFileName);
		var all = new HashSet<(string Package, string Version)>(initial, TupleComparer.Instance);
		var missing = new HashSet<(string Package, string Version)>(initial, TupleComparer.Instance);

		int added = ExpandDependencies(all, missing);

		RemoveExistingPackages(all);

		WriteCsv(all, _dataFileName);
		WriteCsv(missing, _missingFileName);

		Console.WriteLine();
		Console.WriteLine("===== Transitive Package Expansion Summary =====");
		Console.WriteLine($"Input packages:           {initial.Count}");
		Console.WriteLine($"New transitive packages:  {added}");
		Console.WriteLine($"Missing parent packages:  {missing.Count}");
		Console.WriteLine($"Total unique packages:    {all.Count}");
		Console.WriteLine($"Search expanded:          {_searchExpanded}");
		Console.WriteLine($"Search nupkg:             {_searchNupkg}");
		if (_searchExpanded)
		{
			Console.WriteLine("Expanded folders:");
			foreach (var f in _expandedFolders)
			{
				Console.WriteLine($"  - {f}");
			}
		}
		if (_searchNupkg)
		{
			Console.WriteLine("Nupkg folders:");
			foreach (var f in _nupkgFolders)
			{
				Console.WriteLine($"  - {f}");
			}
		}

		Console.WriteLine($"Output file:              {_dataFileName}");
		Console.WriteLine("================================================");
		Console.WriteLine();
	}

	private void RemoveExistingPackages(HashSet<(string Package, string Version)> all)
	{
		if (!Convert.ToBoolean(_configuration["PackageScanner:RemoveMissingPackagesFromDataFile"]))
		{
			return; 
		}

		foreach (var package in all)
		{
			foreach (var root in _nupkgFolders)
			{
				string file = Path.Combine(root, $"{package.Package}.{package.Version}.nupkg");

				if (File.Exists(file))
				{
					all.Remove(package);
				}
			}
		}
	}

	private int ExpandDependencies(HashSet<(string Package, string Version)> all, HashSet<(string Package, string Version)> missing)
	{
		int before = all.Count;

		var queue = new Queue<(string Package, string Version)>(all);
		var removeMissingPackagesFromDataFile = Convert.ToBoolean(_configuration["PackageScanner:RemoveMissingPackagesFromDataFile"]);

		while (queue.Count > 0)
		{
			var pkg = queue.Dequeue();

			string? path = FindPackageSource(pkg.Package, pkg.Version);

			if (string.IsNullOrEmpty(path))
			{
				missing.Add(pkg);
				if (removeMissingPackagesFromDataFile)
				{
					all.Remove(pkg);
				}
				continue;
			}
			else
			{
				foreach (var dep in GetDependencies(path))
				{
					if (all.Add(dep))
					{
						queue.Enqueue(dep);
					}
				}
			}
		}

		return all.Count - before;
	}

	private IEnumerable<(string Package, string Version)> GetDependencies(string path)
	{

		XDocument doc;
		if (path.EndsWith(".nupkg", StringComparison.OrdinalIgnoreCase))
		{
			using var zip = ZipFile.OpenRead(path);
			var nuspecEntry = zip.Entries.FirstOrDefault(e =>
				e.FullName.EndsWith(".nuspec", StringComparison.OrdinalIgnoreCase));

			if (nuspecEntry == null)
				yield break;

			using var stream = nuspecEntry.Open();
			doc = XDocument.Load(stream);
		}
		else
		{
			doc = XDocument.Load(path);
		}

		foreach (var element in doc.Descendants())
		{
			if (!element.ToString().StartsWith("<dependency", StringComparison.CurrentCultureIgnoreCase))
			{
				continue;
			}

			var dependencyId = element.Attribute("id")?.Value;
			var dependencyVersion = element.Attribute("version")?.Value;

			if (!string.IsNullOrWhiteSpace(dependencyId) && !string.IsNullOrWhiteSpace(dependencyVersion))
			{
				yield return (dependencyId!, dependencyVersion!);
			}
		}
	}



	private string? FindPackageSource(string id, string version)
	{
		string lowerId = id.ToLowerInvariant();
		string lowerVersion = version.ToLowerInvariant();

		// 1. Expanded folders
		if (_searchExpanded)
		{
			foreach (var root in _expandedFolders)
			{
				string folder = Path.Combine(root, lowerId, lowerVersion);
				string nuspec = Path.Combine(folder, $"{id}.nuspec");

				if (File.Exists(nuspec))
					return nuspec;
			}
		}

		// 2. Raw .nupkg folders
		if (_searchNupkg)
		{
			foreach (var root in _nupkgFolders)
			{
				string file = Path.Combine(root, $"{id}.{version}.nupkg");

				if (File.Exists(file))
				{
					return file;
				}
			}
		}

		return null;
	}

	private static List<(string Package, string Version)> LoadCsv(string path)
	{
		var list = new List<(string Package, string Version)>();

		foreach (var line in File.ReadLines(path).Skip(1))
		{
			var parts = line.Split(',');
			if (parts.Length == 2)
			{
				var package = parts[0].Trim('"');
				var version = parts[1].Trim('"');
				list.Add((package, version));
			}
		}

		return list;
	}

	private static string ResolveDataFile(string? path, string filename)
	{
		if (!string.IsNullOrWhiteSpace(path))
		{
			return Path.Combine(path!, filename);
		}

		var downloads = Path.Combine(
			Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
			"Downloads");

		return Path.Combine(downloads, filename);
	}

	private void WriteCsv(IEnumerable<(string Package, string Version)> packages, string filename)
	{
		using var writer = new StreamWriter(filename);

		writer.WriteLine("\"Package\",\"Version\"");

		foreach (var (package, version) in packages.OrderBy(p => p.Package).ThenBy(p => p.Version))
		{
			writer.WriteLine($"\"{package}\",\"{version}\"");
		}
	}


	private sealed class TupleComparer : IEqualityComparer<(string Package, string Version)>
	{
		public static readonly TupleComparer Instance = new();

		public bool Equals((string Package, string Version) x, (string Package, string Version) y)
			=> StringComparer.OrdinalIgnoreCase.Equals(x.Package, y.Package) &&
			   StringComparer.OrdinalIgnoreCase.Equals(x.Version, y.Version);

		public int GetHashCode((string Package, string Version) obj)
			=> HashCode.Combine(
				StringComparer.OrdinalIgnoreCase.GetHashCode(obj.Package),
				StringComparer.OrdinalIgnoreCase.GetHashCode(obj.Version));
	}
}
