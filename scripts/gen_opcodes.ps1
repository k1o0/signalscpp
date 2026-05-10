<#
.SYNOPSIS
    Generate matlab/+sig/OpCode.m from Signals/transferer.h.

.DESCRIPTION
    Parses the C++ 'enum class Operation' block in transferer.h and emits a
    MATLAB enumeration classdef (< uint32) with one member for each enumerator.

    Run automatically as a CMake PRE_BUILD step on signalsproxy so that the
    MATLAB opcode enum is always regenerated from the same header used by the
    C++ compiler - the two can never silently diverge.

    Can also be called directly:
        powershell -File scripts\gen_opcodes.ps1

    MATLAB reserved keywords (e.g. 'function', 'end') are suffixed with '_op'
    to prevent parse errors in the generated file.

.PARAMETER HeaderFile
    Path to Signals/transferer.h.
    Defaults to the file relative to this script's location in scripts/.

.PARAMETER OutputFile
    Destination MATLAB file.
    Defaults to matlab/+sig/OpCode.m relative to the repo root.

.EXAMPLE
    # From the repo root:
    powershell -File scripts\gen_opcodes.ps1

    # Explicit paths:
    powershell -File scripts\gen_opcodes.ps1 `
        -HeaderFile Signals\transferer.h `
        -OutputFile matlab\+sig\OpCode.m
#>

param(
    [string]$HeaderFile = (Join-Path $PSScriptRoot '..\Signals\transferer.h'),
    [string]$OutputFile = (Join-Path $PSScriptRoot '..\matlab\+sig\OpCode.m')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# MATLAB reserved keywords that cannot be used as Constant property names.
# If a C++ enumerator name matches one of these it gets an '_op' suffix.
$matlabKeywords = @(
    'break','case','catch','classdef','continue','else','elseif','end',
    'for','function','global','if','otherwise','parfor','persistent',
    'return','spmd','switch','try','while'
)

# MATLAB uint32 inherited method names that would clash with enumeration members.
# These are also suffixed with '_op' to avoid "cannot be used for both a method
# and a member of an enumeration class" errors.
$matlabMethods = @(
    'plus','minus','times','mtimes','rdivide','ldivide','mrdivide','mldivide',
    'power','mpower','uminus','uplus',
    'eq','ne','lt','le','gt','ge',
    'and','or','not',
    'ctranspose','transpose',
    'colon','horzcat','vertcat',
    'subsref','subsasgn','subsindex',
    'abs','sign','floor','ceil','round','mod','rem',
    'sum','prod','cumsum','cumprod',
    'max','min','sort',
    'any','all',
    'numel','size','length','ndims','isempty','isnumeric','islogical',
    'display','disp','char','string','double','single','logical',
    'int8','int16','int32','int64','uint8','uint16','uint32','uint64'
)

# ---------------------------------------------------------------------------
# Parse the header
# ---------------------------------------------------------------------------
$content = Get-Content $HeaderFile -Raw -ErrorAction Stop

if ($content -notmatch '(?s)enum\s+class\s+\w+\s+Operation\s*\{(.+?)\};') {
    Write-Error "Could not find 'enum class Operation' in $HeaderFile"
    exit 1
}
$enumBody = $Matches[1]

$entries = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($line in ($enumBody -split "`n")) {
    # Strip inline comments and trailing whitespace/comma
    $stripped = ($line -replace '//.*$', '').Trim().TrimEnd(',').Trim()

    if ($stripped -match '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(\d+)$') {
        $name = $Matches[1]
        $val  = [int]$Matches[2]

        if ($matlabKeywords -contains $name -or $matlabMethods -contains $name) { $name = "${name}_op" }

        $entries.Add([PSCustomObject]@{ Name = $name; Value = $val })
    }
}

if ($entries.Count -eq 0) {
    Write-Error "No enum members parsed from $HeaderFile - check the regex"
    exit 1
}

$sorted = $entries | Sort-Object Value

# ---------------------------------------------------------------------------
# Emit the MATLAB enumeration classdef
# ---------------------------------------------------------------------------

# Build the dynamic enumeration member lines first so they can be spliced into
# the here-string via normal variable expansion.
$members = ($sorted | ForEach-Object {
    "        $($_.Name.PadRight(14)) ($($_.Value))"
}) -join [System.Environment]::NewLine

# Double-quoted here-string: variables expand, backslashes are literal (no
# escape sequences in PowerShell here-strings).  No single-quote delimiters
# are used so the file is immune to smart-quote encoding issues.
$matlab = @"
classdef OpCode < uint32
% sig.OpCode  Integer opcodes for signal network node operations.
%
% AUTO-GENERATED - do not edit by hand.
% Source:    Signals/transferer.h  (enum class Operation)
% Generator: scripts/gen_opcodes.ps1
%
% This file is rebuilt as a CMake PRE_BUILD step on signalsproxy,
% ensuring the MATLAB enum always matches the C++ enum.
% To regenerate manually from the repo root:
%   powershell -File scripts\gen_opcodes.ps1
%
% Usage:
%   net.addNode(src, sig.OpCode.map_op,  false, fn)
%   net.addNode([],  sig.OpCode.nop,     false)
%
% See also sig.Net.addNode, sig.node.Signal, Signals/transferer.h

    enumeration
$members
    end
end
"@

# Write UTF-8 without BOM (MATLAB is fine with either; no-BOM is cleaner)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($OutputFile, $matlab, $utf8NoBom)

Write-Host "[gen_opcodes] $($sorted.Count) opcodes written to $OutputFile"
