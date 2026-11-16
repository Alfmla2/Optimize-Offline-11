Function Optimize-InstallMedia
{
    [CmdletBinding()]
    Param ()

    $ISOMedia = Import-DataFile -ISOMedia -ErrorAction:$ErrorActionPreference
    $InstallInfo = Import-DataFile Install -ErrorAction:$ErrorActionPreference
    $ISOSources = (GetPath -Path $ISOMedia.FullName -Child sources -ErrorAction:$ErrorActionPreference)
    # Remove items only used for upgrading from inside Windows (the media still boots and installs without them).
    @((Get-ChildItem -Path $ISOMedia.FullName -Filter *.dll), (GetPath -Path $ISOMedia.FullName -Child autorun.inf), (GetPath -Path $ISOMedia.FullName -Child setup.exe), (GetPath -Path $ISOMedia.FullName -Child ca), (GetPath -Path $ISOMedia.FullName -Child NanoServer), (GetPath -Path $ISOMedia.FullName -Child support), (GetPath -Path $ISOMedia.FullName -Child upgrade)) | Purge -ErrorAction:$ErrorActionPreference
    # Remove Setup language folders other than the image language (e.g. ca-es, vi-vn). Non-language folders are kept.
    Get-ChildItem -Path $ISOSources -Directory | Where-Object { $PSItem.Name -match '^[a-z]{2,3}-[a-z]{2,4}$' -and $PSItem.Name -ne $InstallInfo.Language } | Purge -ErrorAction:$ErrorActionPreference
    # Everything else in \sources is kept. Since 24H2, Setup (both the new and the previous version) runs setuphost.exe from the
    # media's \sources folder, which loads the DLLs, manifests and language resources next to it; stripping them made Setup fail
    # at the start of the installation ("Windows 11 installation has failed"). Keeping them adds about 150 MB to the ISO.
    If ($DynamicParams.NetFx3) { (GetPath -Path $ISOSources -Child sxs) | Purge -ErrorAction:$ErrorActionPreference }
}
