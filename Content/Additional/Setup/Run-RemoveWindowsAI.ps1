$Options = @(
    'DisableRegKeys',
    'PreventAIPackageReinstall',
    'DisableCopilotPolicies',
    'RemoveAppxPackages',
    'RemoveRecallFeature',
    'RemoveCBSPackages',
    'RemoveAIFiles',
    'HideAIComponents',
    'DisableRewrite',
    'RemoveWindowsAITasks',
    'UpdateCleanupCheck',
    'DisableDefenderAI'
)

& (Join-Path $PSScriptRoot 'RemoveWindowsAI.ps1') -nonInteractive -Options $Options
