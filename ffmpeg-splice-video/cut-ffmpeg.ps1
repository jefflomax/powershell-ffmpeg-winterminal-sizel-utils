
Param(
[Parameter(ValueFromPipeline = $true, Position = 0, Mandatory=$false)][string]$imageFile,
[Parameter(Mandatory=$false)][string]$Seg1Start, # Zero if empty
[Parameter(Mandatory=$false)][string]$Seg1Finish,
[Parameter(Mandatory=$false)][string]$Seg2Start,
[Parameter(Mandatory=$false)][string]$Seg2Finish, # Max Keyframe if empty
[Parameter(Mandatory=$false)][string]$OutputFile="output.mp4"
)

# 7.1-full_build-www.gyan.dev Copyright (c) 2000-2024 the FFmpeg developers
<#
# Setup, all free open source tools, no accounts, online, tracking or selling you.

# Run from non-Admin Windows Terminal
# Installs FFMPEG 7.1 - (Gyan.FFmpeg)
winget install FFmpeg

# Restart your Windows Terminal
#>

# PowerShell 5.1.26100.8085 - the ONLY version released in Windows as of Win11 25H2 and prior

# .\cut-ffmpeg.ps1 -imageFile test1.mp4 -Seg1Start "" -Seg1Finish "00:00:08.000" -Seg2Start "00:00:32.500" -Seg2Finish ""
# .\cut-ffmpeg.ps1 -imageFile test2.mp4 -Seg1Start "" -Seg1Finish "00:00:12.0352330" -Seg2Start "00:00:25.090" -Seg2Finish "" -Verbose


$file = $imageFile

$invCi = [System.Globalization.CultureInfo]::InvariantCulture

Function Parse-Timespan {
Param(
[Parameter()][string]$ts,
[Parameter()][TimeSpan]$lastTS=[TimeSpan]::Zero,
[Parameter()][TimeSpan]$maxTS
)
    If( [string]::IsNullOrEmpty($ts) )
    {
        If( $lastTS -eq [TimeSpan]::Zero ) {
            return [TimeSpan]::Zero
        }
        return $maxTS
    }

    $timeSpan = [TimeSpan]::Zero

    If( [TimeSpan]::TryParse($ts, $invCi, [ref]$timeSpan) ) {
        If( $timeSpan -ge $maxTs ) {
            Write-Error "Timestamp $ts greater than $maxTs"
            Exit
        }

        If( $timeSpan -lt $lastTS ) {
            Write-Error "Timestamp $ts should exceed $lastTS"
            Exit
        } 
        
        return $timeSpan
    }

    Write-Error "Could not parse $ts"
    Exit
}


Function Get-TimestampAfter {
Param(
[Parameter()][TimeSpan]$t,
[Parameter()][System.Array]$ts,
[Parameter()][int]$offset=0
)
    $cur = [TimeSpan]::MinValue
    $index = $offset
    $treshold = $false
    For( $i = $offset; $i -lt $ts.Count; $i++ ) {
        $cur = $ts[$i]

        If( $cur -ge $t ) {
            Write-Verbose "Point $t used key $cur $(If($i -gt 0){'-1 '+$ts[$i-1]}) $(If($i+1 -lt $ts.Count){'+1 '+$ts[$i+1]} )"
            return $i, $cur
        }
    }
    return -1, $cur
}


Function Remove-IfExists {
Param(
[Parameter()][string]$inputFile
)
    If( Test-Path -Path $inputFile ) {
        Get-ChildItem -Path $inputFile | Remove-Item
    }
}

# Validate Input
If( -Not (Test-Path -Path $file) ) {
    Write-Host "File missing $file"
    Return;
}

Remove-IfExists -inputFile cutlist.txt

Remove-IfExists -inputFile output.mp4



$keyFrameTimeSpans = List-Keyframes -inputFile $file

$keyFrameCount = $keyFrameTimeSpans.Count-1
$maxKeyFrameTS = $keyFrameTimeSpans[$keyFrameCount]

Write-Host "Read $($keyFrameTimeSpans.Count) Key Frames from $($keyFrameTimeSpans[0]) to $maxKeyFrameTS"

# only 1 segments to keep for now
$seg1 = Parse-Timespan -ts $Seg1Start -maxTS $maxKeyFrameTS
$seg1e = Parse-Timespan -ts $Seg1Finish -lastTS $seg1 -maxTS $maxKeyFrameTS

$seg2 = Parse-Timespan -ts $Seg2Start -lastTS $seg1e -maxTS $maxKeyFrameTS
$seg2e = Parse-Timespan -ts $Seg2Finish -lastTS $seg2 -maxTS $maxKeyFrameTS

Write-Verbose "Parsed $seg1 $seg1e,  $seg2 $seg2e"

$keep1Frame, $keep1BeginTS = Get-TimestampAfter -t $seg1 -ts $keyFrameTimeSpans
$keep1eFrame, $keep1EndTS = Get-TimestampAfter -t $seg1e -ts $keyFrameTimeSpans -offset $keep1Frame

$keep2Frame, $keep2BeginTS = Get-TimestampAfter -t $seg2 -ts $keyFrameTimeSpans -offset $keep1eFrame
$keep2eFrame, $keep2EndTS = Get-TimestampAfter -t $seg2e -ts $keyFrameTimeSpans -offset $keep2Frame 

#$keep2EndTS = $keyFrameTimeSpans[$keyFrameCount] # EOF


Write-Host "Cut $file keeping $keep1BeginTS - $keep1EndTS and $keep2BeginTS - $keep2EndTS"

# concat is absurdly picky, many posters say the input file must be UTF8 without a BOM
# Better to use ascii if you can

$inNudge = [TimeSpan]::FromMilliseconds(1)

$cutlist = @"
file '$($file)'
inpoint $($keep1BeginTS.Add($inNudge))
outpoint $($keep1EndTS)
file '$($file)'
inpoint $($keep2BeginTS.Add($inNudge))
outpoint $($keep2EndTS)
"@
$cutlist | Out-File cutlist.txt -Encoding ascii

# https://trac.ffmpeg.org/wiki/Concatenate
# -safe 1 can be used for relative files without special chars
& ffmpeg -loglevel error -f concat -safe 0 -i cutlist.txt -c copy $OutputFile

Write-Verbose $cutlist
