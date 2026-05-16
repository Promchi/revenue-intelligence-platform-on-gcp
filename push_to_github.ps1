# PowerShell script to push this dbt project to GitHub.
# Run from the project root in PowerShell:
#   cd "C:\Users\Ezeike Promse Chime\Desktop\revenue-intelligence-platform\revenue_intelligence_platform"
#   .\push_to_github.ps1
#
# If you get an execution-policy error, run this once first:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

$ErrorActionPreference = "Stop"
$RemoteUrl  = "https://github.com/Promchi/revenue-intelligence-platform-on-gcp.git"
$CommitMsg  = "Initial commit: dbt project for revenue intelligence platform on GCP/BigQuery (CRM, ERP, and web staging models; intermediate customer/payment/sales aggregations; core, finance, and marketing marts)"

Write-Host "==> Initializing git repository (if needed)..."
if (-not (Test-Path ".git")) {
    git init
    git branch -M main
} else {
    Write-Host "    .git already exists, skipping init."
}

Write-Host "==> Staging files (respecting .gitignore)..."
git add .

Write-Host "==> Checking what will be committed..."
git status --short

Write-Host "==> Committing..."
git commit -m $CommitMsg

Write-Host "==> Configuring remote 'origin'..."
$existing = git remote 2>$null
if ($existing -contains "origin") {
    git remote set-url origin $RemoteUrl
} else {
    git remote add origin $RemoteUrl
}

Write-Host "==> Pushing to GitHub (you may be prompted to authenticate)..."
git push -u origin main

Write-Host ""
Write-Host "Done. View your repo at: https://github.com/Promchi/revenue-intelligence-platform-on-gcp"
