using BenchmarkDotNet.Configs;
using BenchmarkDotNet.Environments;
using BenchmarkDotNet.Jobs;
using BenchmarkDotNet.Running;

var config = ManualConfig.Create(DefaultConfig.Instance)
    .AddJob(Job.ShortRun.WithLaunchCount(2).WithWarmupCount(3).WithIterationCount(5)
        .WithPowerPlan(PowerPlan.UserPowerPlan));
var summaries = BenchmarkSwitcher.FromAssembly(typeof(Program).Assembly).Run(args, config).ToArray();
if (summaries.Length == 0 || summaries.Any(summary => summary.HasCriticalValidationErrors ||
    summary.Reports.Length == 0 || summary.Reports.Any(report => !report.Success || report.ResultStatistics is null)))
{
    Console.Error.WriteLine("No complete benchmark result. Review the validation and execution errors.");
    return 1;
}

return 0;
