#Requires -RunAsAdministrator
<#
  Partage la connexion Wi-Fi (eduroam) du PC vers l'adaptateur Ethernet relié au switch
  (Partage de connexion Internet / ICS), et le rend persistant après redémarrage.

  Usage (PowerShell administrateur) :
    .\setup-ics.ps1                                  # Wi-Fi -> Ethernet
    .\setup-ics.ps1 -Public "Wi-Fi" -Private "Ethernet 2"
    .\setup-ics.ps1 -Disable                         # coupe le partage
#>
param(
  [string]$Public = "Wi-Fi",
  [string]$Private = "Ethernet",
  [switch]$Disable
)
$ErrorActionPreference = 'Stop'

$share = New-Object -ComObject HNetCfg.HNetShare

function Get-SharingConfig([string]$name) {
  foreach ($c in $share.EnumEveryConnection) {
    if ($share.NetConnectionProps.Invoke($c).Name -eq $name) {
      return $share.INetSharingConfigurationForINetConnection.Invoke($c)
    }
  }
  $names = foreach ($c in $share.EnumEveryConnection) { $share.NetConnectionProps.Invoke($c).Name }
  throw "Adaptateur '$name' introuvable. Adaptateurs disponibles : $($names -join ', ')"
}

# Un seul partage ICS possible à la fois : on coupe tout ce qui existe
foreach ($c in $share.EnumEveryConnection) {
  $cfg = $share.INetSharingConfigurationForINetConnection.Invoke($c)
  if ($cfg.SharingEnabled) { $cfg.DisableSharing() }
}

if ($Disable) {
  Write-Host "Partage de connexion désactivé."
  return
}

$pub = Get-SharingConfig $Public
$priv = Get-SharingConfig $Private
$pub.EnableSharing(0)   # 0 = connexion publique (vers Internet)
$priv.EnableSharing(1)  # 1 = connexion privée (vers le switch)

# Garder le partage actif après un redémarrage de Windows
New-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\SharedAccess" `
  -Name EnableRebootPersistConnection -Value 1 -PropertyType DWORD -Force | Out-Null
Set-Service SharedAccess -StartupType Automatic

Write-Host "OK : '$Public' est partagé vers '$Private' (réseau 192.168.137.0/24, PC = 192.168.137.1)."
