using System.Xml.Linq;

using Microsoft.Extensions.Configuration;
namespace NugetPackageDownloader;

public sealed class NuGetPackageScanner
{
	private readonly bool _enabled;
	private readonly IReadOnlyList<string> _searchRoots;
	private readonly string _dataFile;
	private readonly IConfigurationRoot _configuration;

	public NuGetPackageScanner(IConfigurationRoot configuration)
	{
		_configuration = configuration;
		_enabled = Convert.ToBoolean(_configuration["PackageScanner:Enabled"]);
		_searchRoots = _configuration.GetSection("PackageScanner:SearchLocations").GetChildren().Select(x => ResolvePath(x.Value!)).ToList() ?? [];
		_dataFile = ResolveDataFile(_configuration["Globals:DataFile"], _configuration["Globals:DataFileName"]!);
	}

	private static string ResolvePath(string path)
	{
		return path.Replace("%USERPROFILE%", Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
	}

	public void Run()
	{
		if (!_enabled)
		{
			Console.WriteLine("PackageScanner.Enabled = false. Scanner will not run.");
			return;
		}

		int solutionCount = 0;
		int projectCount = 0;
		int packageRefCount = 0;

		var allPackages = new HashSet<(string Package, string Version)>(StringTupleComparer.Instance);

		foreach (var root in _searchRoots)
		{
			if (!Directory.Exists(root))
				continue;

			foreach (var sln in Directory.EnumerateFiles(root, "*.sln", SearchOption.AllDirectories))
			{
				solutionCount++;

				var solutionDir = Path.GetDirectoryName(sln)!;

				foreach (var csproj in Directory.EnumerateFiles(solutionDir, "*.csproj", SearchOption.AllDirectories))
				{
					projectCount++;

					foreach (var pkg in ExtractPackages(csproj))
					{
						packageRefCount++;
						allPackages.Add(pkg);
					}
				}
			}
		}

		WriteCsv(allPackages);

		Console.WriteLine();
		Console.WriteLine("===== Package Scanner Summary ==============================");
		Console.WriteLine($"Solutions scanned        : {solutionCount}");
		Console.WriteLine($"Projects scanned         : {projectCount}");
		Console.WriteLine($"Package references found : {packageRefCount}");
		Console.WriteLine($"Unique packages written  : {allPackages.Count}");
		Console.WriteLine($"Data file                : {_dataFile}");
		Console.WriteLine("============================================================");
		Console.WriteLine();
	}

	private static IEnumerable<(string Package, string Version)> ExtractPackages(string csprojPath)
	{
		XDocument doc;

		try
		{
			doc = XDocument.Load(csprojPath);
		}
		catch
		{
			yield break;
		}
		foreach (var packageReference in doc.Descendants("PackageReference"))
		{
			var id = packageReference.Attribute("Include")?.Value;
			var version = packageReference.Attribute("Version")?.Value;
			if (version!.Contains(','))
			{
				var packages = NuGetVersionResolver.GetValidVersionsAsync(id!, version).GetAwaiter().GetResult();
				foreach (var item in packages)
				{
					Console.WriteLine(item);
				}
			}
			if (!string.IsNullOrWhiteSpace(id) && !string.IsNullOrWhiteSpace(version))
				yield return (id!, version!);
		}
	}

	private void WriteCsv(IEnumerable<(string Package, string Version)> packages)
	{
		using var writer = new StreamWriter(_dataFile);

		writer.WriteLine("\"Package\",\"Version\"");

		var sorted = packages
			.OrderBy(p => p.Package, StringComparer.OrdinalIgnoreCase)
			.ThenBy(p => p.Version, StringComparer.OrdinalIgnoreCase);

		foreach (var (pkg, ver) in sorted)
			writer.WriteLine($"\"{pkg}\",\"{ver}\"");
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

	private sealed class StringTupleComparer : IEqualityComparer<(string Package, string Version)>
	{
		public static readonly StringTupleComparer Instance = new();

		public bool Equals((string Package, string Version) x, (string Package, string Version) y)
			=> StringComparer.OrdinalIgnoreCase.Equals(x.Package, y.Package) &&
			   StringComparer.OrdinalIgnoreCase.Equals(x.Version, y.Version);

		public int GetHashCode((string Package, string Version) obj)
			=> HashCode.Combine(
				StringComparer.OrdinalIgnoreCase.GetHashCode(obj.Package),
				StringComparer.OrdinalIgnoreCase.GetHashCode(obj.Version));
	}
}
