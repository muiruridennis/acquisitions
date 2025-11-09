#!/usr/bin/env pwsh
# Create required Kubernetes secrets for local development

param(
  [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"

function Ensure-Namespace {
  param([string]$Name)
  $null = kubectl get ns $Name 2>$null
  if ($LASTEXITCODE -ne 0) { kubectl create namespace $Name | Out-Null }
}

function ConvertFrom-SecureStringPlain {
  param([SecureString]$Secure)
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try { [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

$ns = 'acquisitions-local'
Ensure-Namespace $ns

# neon-local-secret (for Neon Local Deployment)
$proj = $env:NEON_PROJECT_ID
$key  = $env:NEON_API_KEY

if (-not $NonInteractive) {
  if (-not $proj) { $proj = ConvertFrom-SecureStringPlain (Read-Host -AsSecureString -Prompt 'Enter NEON_PROJECT_ID') }
  if (-not $key)  { $key  = ConvertFrom-SecureStringPlain (Read-Host -AsSecureString -Prompt 'Enter NEON_API_KEY') }
}

if (-not $proj -or -not $key) {
  Write-Error 'NEON_PROJECT_ID and NEON_API_KEY must be provided (env vars or interactive input).'
  exit 1
}

kubectl -n $ns create secret generic neon-local-secret `
  --from-literal=NEON_PROJECT_ID=$proj `
  --from-literal=NEON_API_KEY=$key `
  --dry-run=client -o yaml | kubectl apply -f -

# acquisitions-app-secret (for the app itself) — local values
$databaseUrl = $env:DATABASE_URL
if (-not $databaseUrl) { $databaseUrl = 'postgres://neon:neon@neon-local:5432/neondb' }
$arcjetKey = $env:ARCJET_KEY
if (-not $arcjetKey) { $arcjetKey = 'ajkey_local_dev' }

kubectl -n $ns create secret generic acquisitions-app-secret `
  --from-literal=DATABASE_URL=$databaseUrl `
  --from-literal=ARCJET_KEY=$arcjetKey `
  --dry-run=client -o yaml | kubectl apply -f -

Write-Host "Secrets created/updated in namespace '$ns'" -ForegroundColor Green
