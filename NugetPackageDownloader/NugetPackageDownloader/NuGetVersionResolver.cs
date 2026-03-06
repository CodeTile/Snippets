namespace NugetPackageDownloader;

using NuGet.Common;
using NuGet.Protocol;
using NuGet.Protocol.Core.Types;
using NuGet.Versioning;

public static class NuGetVersionResolver
{
	private static readonly SourceRepository Repo =
		Repository.Factory.GetCoreV3("https://api.nuget.org/v3/index.json");

	public static async Task<List<string>> GetValidVersionsAsync(
		string packageId,
		string versionRangeString)
	{
		if (string.IsNullOrWhiteSpace(packageId))
			throw new ArgumentException("Package ID cannot be empty.", nameof(packageId));

		if (string.IsNullOrWhiteSpace(versionRangeString))
			throw new ArgumentException("Version range cannot be empty.", nameof(versionRangeString));

		var range = VersionRange.Parse(versionRangeString);
		var resource = await Repo.GetResourceAsync<FindPackageByIdResource>();

		var allVersions = await resource.GetAllVersionsAsync(
			packageId,
			new SourceCacheContext(),
			NullLogger.Instance,
			default);

		return allVersions
			.Where(v => !v.IsPrerelease)          // no prerelease
			.Where(v => range.Satisfies(v))       // apply range
			.Select(v => v.ToNormalizedString())  // convert to string
			.ToList();
	}
}
