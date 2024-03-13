# SPDX-License-Identifier: Apache-2.0
# Licensed to the Ed-Fi Alliance under one or more agreements.
# The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
# See the LICENSE and NOTICES files in the project root for more information.

[CmdLetBinding()]
<#
    .SYNOPSIS
        Automation script for running build operations from the command line.

    .DESCRIPTION
        Provides automation of the following tasks:

        * Clean: runs `dotnet clean`
        * Build: runs `dotnet build` with several implicit steps
          (clean, restore, inject version information).
        * UnitTest: executes NUnit tests in projects named `*.UnitTests`, which
          do not connect to a database.
        * E2ETest: executes NUnit tests in projects named `*.E2ETests`, which
          runs the API in an isolated Docker environment and executes API Calls .
        * BuildAndPublish: build and publish with `dotnet publish`
        * DockerBuild: builds a Docker image from source code
        * DockerRun: runs the Docker image that was built from source code
    .EXAMPLE
        .\build.ps1 build -Configuration Release -Version "2.0" -BuildCounter 45

        Overrides the default build configuration (Debug) to build in release
        mode with assembly version 2.0.45.

    .EXAMPLE
        .\build.ps1 unittest

        Output: test results displayed in the console and saved to XML files.

    .EXAMPLE
        .\build.ps1 DockerBuild
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'False positive')]
param(
    # Command to execute, defaults to "Build".
    [string]
    [ValidateSet("Clean", "Build", "BuildAndPublish", "UnitTest", "E2ETest", "DockerBuild", "DockerRun")]
    $Command = "Build",

    # Assembly and package version number for the Data Management Service. The
    # current package number is configured in the build automation tool and
    # passed to this script.
    [string]
    $DMSVersion = "0.1",

    # .NET project build configuration, defaults to "Debug". Options are: Debug, Release.
    [string]
    [ValidateSet("Debug", "Release")]
    $Configuration = "Debug",

    [bool]
    $DryRun = $false,

    # Ed-Fi's official NuGet package feed for package download and distribution.
    [string]
    $EdFiNuGetFeed = "https://pkgs.dev.azure.com/ed-fi-alliance/Ed-Fi-Alliance-OSS/_packaging/EdFi/nuget/v3/index.json",

    # Only required with local builds and testing.
    [switch]
    $IsLocalBuild
)

$solutionRoot = "$PSScriptRoot/src"
$defaultSolution = "$solutionRoot/EdFi.DataManagementService.sln"
$servicesRoot = "$solutionRoot/services"
$projectName =  "EdFi.DataManagementService.Api"
$testResults = "$PSScriptRoot/TestResults"

Import-Module -Name "$PSScriptRoot/eng/build-helpers.psm1" -Force

function DotNetClean {
    Invoke-Execute { dotnet clean $defaultSolution -c $Configuration --nologo -v minimal }
}

function Restore {
    Invoke-Execute { dotnet restore $defaultSolution }
}

function Compile {
    Invoke-Execute {
        dotnet build $defaultSolution -c $Configuration --nologo --no-restore
    }
}

function PublishApi {
    Invoke-Execute {
        $project = "$servicesRoot/$projectName/"
        $outputPath = "$project/publish"
        dotnet publish $project -c $Configuration /p:EnvironmentName=Production -o $outputPath --no-build --nologo
    }
}

function RunTests {
    param (
        # File search filter
        [string]
        $Filter
    )

    $testAssemblyPath = "$servicesRoot/$Filter/bin/$Configuration/"
    $testAssemblies = Get-ChildItem -Path $testAssemblyPath -Filter "$Filter.dll" -Recurse

    if ($testAssemblies.Length -eq 0) {
        Write-Output "no test assemblies found in $testAssemblyPath"
    }

    $testAssemblies | ForEach-Object {
        Write-Output "Executing: dotnet test $($_)"

        $fileName = Split-Path -Path  $($_) -Leaf
        $fileNameNoExt = $fileName.subString(0, $fileName.length-4)

        Invoke-Execute {
            dotnet test $_ `
                --logger "trx;LogFileName=$testResults/$fileNameNoExt.trx" `
                --nologo
        }
    }
}

function UnitTests {
    Invoke-Execute { RunTests -Filter "*.Tests.Unit" }
}

function RunE2E {
    Invoke-Execute { RunTests -Filter "*.Tests.E2E" }
}

function E2ETests {
    Invoke-Step { DockerBuild }
    Invoke-Step { RunE2E }
}

function Invoke-Build {
    Invoke-Step { DotNetClean }
    Invoke-Step { Restore }
    Invoke-Step { Compile }
}

function Invoke-SetAssemblyInfo {
    Write-Output "Setting Assembly Information"

    Invoke-Step { SetAdminApiAssemblyInfo }
}

function Invoke-Publish {
    Write-Output "Building Version ($DMSVersion)"

    Invoke-Step { PublishApi }
}

function Invoke-Clean {
    Invoke-Step { DotNetClean }
}

function Invoke-UnitTestSuite {
    Invoke-Step { UnitTests }
}

function Invoke-E2ETestSuite {
    Invoke-Step { E2ETests }
}

$dockerTagBase = "local"
$dockerTagDMS = "$($dockerTagBase)/edfi-data-management-service"
function DockerBuild {
    Push-Location src/
    &docker build -t $dockerTagDMS .
    Pop-Location
}

function DockerRun {
    &docker run --rm -p 8080:8080 -d $dockerTagDMS
}

Invoke-Main {
    if($IsLocalBuild)
    {
        $nugetExePath = Install-NugetCli
        Set-Alias nuget $nugetExePath -Scope Global -Verbose
    }
    switch ($Command) {
        Clean { Invoke-Clean }
        Build { Invoke-Build }
        BuildAndPublish {
            Invoke-SetAssemblyInfo
            Invoke-Build
            Invoke-Publish
        }
        UnitTest { Invoke-UnitTestSuite }
        E2ETest { Invoke-E2ETestSuite }
        DockerBuild { Invoke-Step { DockerBuild } }
        DockerRun { Invoke-Step { DockerRun } }
        default { throw "Command '$Command' is not recognized" }
    }
}
