<#
	===========================================================================
	 Filename:     	Optimize-Offline.psd1
	 -------------------------------------------------------------------------
	 Module Manifest — Home fork (fmla-0.1-24H2)
	 Based on original Optimize-Offline by Ben White (BenTheGreat)
	===========================================================================
#>

@{
	GUID                   = 'b8e4a7c2-5d3f-4a91-9c8e-1f2b3d4a5c6e'
	RootModule             = 'Optimize-Offline.psm1'
	ModuleVersion          = '0.1'
	Author                 = 'Ben White; gdeliana (fmla home fork)'
	CompanyName            = 'Home fork'
	Copyright              = '(c) 2026. All rights reserved.'
	Description            = 'Optimize-Offline fork (fmla-0.1-24H2): offline optimization of Windows 10/11 images (WIM/ESD/SWM/ISO) for optimal runtime environments.'
	PowerShellVersion      = '5.1'
	DotNetFrameworkVersion = '4.0'
	CLRVersion             = '4.0'
	ProcessorArchitecture  = 'Amd64'
	RequiredModules        = @('Dism')
	FunctionsToExport      = @('Optimize-Offline')
	CmdletsToExport        = @()
	VariablesToExport      = @()
	AliasesToExport        = @()
	PrivateData            = @{
		PSData = @{
			Tags = @(
				'Optimize-Offline', 'Offline Servicing', 'Offline Imaging',
				'WIM', 'ESD', 'SWM', 'ISO', 'DISM',
				'Windows 10', 'Windows 11', '24H2', '25H2', '26H2', 'LTSC', 'IoT Enterprise',
				'Debloat', 'Image Optimization', 'HomeFork', 'GUI'
			)
		}
	}
}