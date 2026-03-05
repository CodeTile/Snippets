using Microsoft.Extensions.Configuration;

using NugetPackageDownloader;

Console.WriteLine("=== NuGet Package Tools ===");
Console.WriteLine();

try
{
	var configuration = new ConfigurationBuilder()
	.AddJsonFile("appsettings.json", optional: false)
	.Build();

	// Package Scanner
	{
		var scanner = new NuGetPackageScanner(configuration);
		scanner.Run(); 
	}

	// Transitive Package Expander
	{
		var expander = new TransitivePackageExpander(configuration);
		expander.Run();
	}
}
catch (Exception ex)
{
	Console.WriteLine();
	Console.WriteLine("A fatal error occurred:");
	Console.WriteLine(ex.Message);
	Console.WriteLine(ex.StackTrace);
}

Console.WriteLine();
Console.WriteLine("Done.");
