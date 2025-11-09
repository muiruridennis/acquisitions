#!/usr/bin/env pwsh
# Smart Local Deployment Script for Acquisitions App

$ErrorActionPreference = "Stop"

function Test-ImageExists {
    param([string]$ImageName)
    try {
        $null = docker manifest inspect $ImageName 2>$null
        return $LASTEXITCODE -eq 0
    } catch { return $false }
}

function Get-GitHash {
    try { git rev-parse --short HEAD } catch { "unknown" }
}

function Ensure-Namespace {
    param([string]$Name)
    $null = kubectl get ns $Name 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Creating namespace $Name..." -ForegroundColor Yellow
        kubectl create namespace $Name | Out-Null
    }
}

function ConvertFrom-SecureStringPlain {
    param([SecureString]$Secure)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Ensure-NeonLocalSecret {
    param([string]$Namespace)
    $null = kubectl -n $Namespace get secret neon-local-secret -o name 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Secret neon-local-secret already exists in $Namespace" -ForegroundColor DarkGray
        return
    }

    Write-Host "Creating secret neon-local-secret in $Namespace..." -ForegroundColor Yellow

    $proj = $env:NEON_PROJECT_ID
    if (-not $proj) {
        $projSec = Read-Host -AsSecureString -Prompt 'Enter NEON_PROJECT_ID'
        $proj = ConvertFrom-SecureStringPlain $projSec
    }

    $key = $env:NEON_API_KEY
    if (-not $key) {
        $keySec = Read-Host -AsSecureString -Prompt 'Enter NEON_API_KEY'
        $key = ConvertFrom-SecureStringPlain $keySec
    }

    if (-not $proj -or -not $key) { throw "NEON_PROJECT_ID/NEON_API_KEY are required" }

    # Create or update the secret without printing values
    $cmd = @(
        'kubectl', '-n', $Namespace, 'create', 'secret', 'generic', 'neon-local-secret',
        "--from-literal=NEON_PROJECT_ID=$proj",
        "--from-literal=NEON_API_KEY=$key",
        '--dry-run=client', '-o', 'yaml'
    )
    $yaml = & $cmd[0] $cmd[1..($cmd.Length-1)]
    if ($LASTEXITCODE -ne 0) { throw "Failed to render neon-local-secret" }
    $yaml | kubectl apply -f - | Out-Null
}

function Wait-Rollout {
    param([string]$Namespace, [string]$Deployment, [int]$TimeoutSec = 180)
    kubectl -n $Namespace rollout status deploy/$Deployment --timeout=${TimeoutSec}s
    if ($LASTEXITCODE -ne 0) { throw "Rollout failed for $Deployment" }
}

Write-Host "=== Smart Local Deployment ===" -ForegroundColor Green

try {
    $ns = 'acquisitions-local'

    # Always use :latest for local and build it
    $imageTag = "latest"
    $fullImageName = "muiruridennis/acquisitions:$imageTag"
    Write-Host "Using image: $fullImageName" -ForegroundColor Cyan

    # Build the local image
    Write-Host "Building Docker image..." -ForegroundColor Yellow
    docker build -t $fullImageName .
    if ($LASTEXITCODE -ne 0) { throw "Docker build failed" }

    # If using Minikube, load the image into the Minikube node
    $isMinikube = $false
    try {
        $ctx = (kubectl config current-context).Trim()
        if ($ctx -match 'minikube') { $isMinikube = $true }
    } catch {}

    if ($isMinikube -and (Get-Command minikube -ErrorAction SilentlyContinue)) {
        Write-Host "Loading image into Minikube..." -ForegroundColor Yellow
        minikube image load $fullImageName --overwrite

        Write-Host "Ensuring Minikube addons (ingress, metrics-server)..." -ForegroundColor Yellow
        try { minikube addons enable ingress | Out-Null } catch {}
        try { minikube addons enable metrics-server | Out-Null } catch {}
    } else {
        Write-Host "Assuming Docker Desktop Kubernetes shares local images (no push needed)" -ForegroundColor Yellow
    }

    # Ensure namespace and required secrets exist BEFORE apply
    Ensure-Namespace -Name $ns
    Ensure-NeonLocalSecret -Namespace $ns

    # Deploy to Kubernetes
    Write-Host "Deploying to Kubernetes (local overlay)..." -ForegroundColor Yellow
    kubectl apply -k k8s/overlays/local
    if ($LASTEXITCODE -ne 0) { throw "Kubectl apply failed" }

    # Wait for dependent services first
    Write-Host "Waiting for Neon Local to be ready..." -ForegroundColor Yellow
    Wait-Rollout -Namespace $ns -Deployment 'neon-local' -TimeoutSec 240

    Write-Host "Waiting for application to be ready..." -ForegroundColor Yellow
    Wait-Rollout -Namespace $ns -Deployment 'acquisitions-app' -TimeoutSec 240

    # Start port forwarding in background
    Write-Host "Starting port forwarding..." -ForegroundColor Yellow
    $portForwardJob = Start-Job -ScriptBlock {
        kubectl port-forward -n acquisitions-local service/acquisitions-app 8080:80
    }

    Write-Host "App available at: http://localhost:8080" -ForegroundColor Green
    Write-Host "Press Ctrl+C to stop port forwarding" -ForegroundColor Yellow

    while ($true) { Start-Sleep -Seconds 1 }
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
