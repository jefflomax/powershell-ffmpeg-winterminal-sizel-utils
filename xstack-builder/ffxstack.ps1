Param(
[Parameter(Mandatory=$true)][string]$F1,

[Parameter(Mandatory=$false)][string]$SharedPath="",

[Parameter(Mandatory=$false)][string]$F2="",

[Parameter(Mandatory=$false)][string]$F3="",

[Parameter(Mandatory=$false)][string]$F4="",

[Parameter(Mandatory=$false)][string]$Output="c:\temp\tv",

[Parameter(Mandatory=$false)][string]$V0="oscilloscope=x=0.5:y=0:s=1:_ENABLE_30_60_, drawtext=_ENABLE_5_15_:_FONT_BRITANIC_18_:text='%{pts\:hms} %{pict_type}':_FC_PaleGoldenRod_:x=40:y=20",

# This example is letterboxed, applying the inverse filter turns the 'black bars' white
# The fillborders filter erases the letterbox bands so this annoying effect doesn't happen
[Parameter(Mandatory=$false)][string]$V1="negate=_ENABLE_5_10_, fillborders=left=38:right=38:mode=fixed:color=080828",
[Parameter(Mandatory=$false)][string]$V2="hflip=_ENABLE_30_60_, monochrome=_ENABLE_15_60_", #  fade=in:1:900:color=00ffff
[Parameter(Mandatory=$false)][string]$V3="edgedetect=_ENABLE_30_60_, roberts=_NENABLE_30_60_:scale=2:delta=10, drawtext=_ENABLE_30_60_:_FONT_arial_18_:text='Edge Detect':_FC_PaleGoldenRod_:x=10:y=10, drawtext=_NENABLE_30_60_:_FONT_arial_20_:text='Roberts':_FC_PaleGoldenRod_:x=10:y=10 ",

# adding -report in the output parameters
# -crf 23 -report "$outputPath" 
# will capture the real output parms, bugs happen
[Parameter(Mandatory=$false)][bool]$showCommandLineOnly=$false

)
<#
.SYNOPSIS
Run FFMPEG xstack https://ffmpeg.org/ffmpeg-all.html#xstack-1
Such that all 4 videos play until the longest one is complete instead of the shortest.
Blend all audio and don't let short audio stop the playback.

Simple example:
.\ffxstack.ps1 -SharedPath "C:\temp\tv\" -F1 "video\testvideos?.mp4" -Verbose

Adjust a video filter on the 1st file
.\ffxstack.ps1 -SharedPath "C:\temp\tv\" -F1 "video\testvideos?.mp4" -V0 "hflip=_ENABLE_30_60_, monochrome=_ENABLE_15_60_" -Verbose
without the optional RegEx token expansion
.\ffxstack.ps1 -SharedPath "C:\temp\tv\" -F1 "video\testvideos?.mp4" -V0 "hflip=enable=lt(mod(t\,60)\,30), monochrome=enable=lt(mod(t\,60)\,15)" -Verbose

Specify a specific F1 and let F2 wildcard pick 3 more.  It will skip already chosen files
.\ffxstack.ps1 -SharedPath "C:\temp\tv\" -F1 "video\testvideos6.mp4" -F2 "Video\testvideos?.mp4" -Verbose

.DESCRIPTION
PowerShell 5.1 ( still the ONLY version you can depend on being pre-installed as-of Windows 11 26H2 26300.8697 )

Pass the -Verbose flag and set $Debug = $true in the script to get detailed information

There are many examples online, almost all leave you with your video being cut off and the sound mix
terminating when the shortest video ends.
https://stackoverflow.com/questions/11552565/vertically-or-horizontally-stack-mosaic-several-videos-using-ffmpeg

Script uses amix instead of amerge since it support duration=longest and doesn't remove all your audio.
https://ffmpeg.org/ffmpeg-all.html#amix

When this was written it retrieved each video's length and setup TPAD filters on each video.
This is not required when the audio is handled right, but the code is still here as an example
for others who may need to bring a variation of it back.

.PARAMETER SharedPath (Optional)
Fully qualified path prepended to the 4 input videos

.PARAMETER F1 (Required)
Path to video file, can have DOS style * or ? wildcards (System.Management.Automation.WildcardPattern).
SharedPath prepended if provided, otherwise should be a fully qualified path

.PARAMETER F2 (Optional)
Same a F1, ignored if wildcards get to 4 files

.PARAMETER F3 (Optional)
Same a F1, ignored if wildcards get to 4 files

.PARAMETER F4 (Optional)
Same a F1, ignored if wildcards get to 4 files

.PARAMETER Output (Optional)
Fully qualified path or relative path for FFMPEG's output

.NOTES
- This script just builds the input parameters and calls FFMPEG.  
  You can pass -showCommandLineOnly $true to just capture the FFMPEG command line if you prefer.
- FFMPEG can be very sensitive to atypical file names.  NTFS allows characters that often need quoting. PowerShell
  is not very friendly with command line parameters, the extra effort to use Start Process limits how you can use the script.
  If file access presents a problem, rename your input files, assure you have a mapped drive and not a UNC share, it's
  not worth the time.

RegEx Filter Token expansion can simplify entry if you want (RegEx)
Time alternating enable filters.  Since you need multiple enable= to toggle between different
DrawText these make entry shorter and easier
_ENABLE_30_60_   emits enable=lt(mod(t\,60)\,30)        (alternates 30 seconds on/off) 
_NENABLE_30_60_  emits enable=not(lt(mod(t\,60)\,30))   (inverse of above)

fontfile= is a very long filter, this gives a terse entry
_FONT_arial_14_     or _FONT_3_14_   Set font and pointsize by name or index in PowerShell Array

fontcolor= is fairly succinct, this mostly allows specifying an index instead of a name
FontColor
_FC_PaleGoldenRod_  or _FC_2_        Set color by name or index in PowerShell Array

#>

$paramLoop = ("F2","F3","F4")

$ffmpegPath="" # C:\Users\USERNAME\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe
$fontPath = "C\\:/Windows/fonts/" # /Windows/fonts may work

$Debug = $false

$nl = [Environment]::NewLine

# https://ffmpeg.org/ffmpeg-utils.html#toc-Color
# Adjust with your favorite colors
$globalColors = (
"Black",
"DarkBlue",
"DarkTurquoise",
"DarkSlateBlue",
"MediumPurple",
"AliceBlue",
"Aqua",
"Aquamarine",
"PaleGoldenRod"
)

# Get-ChildItem -path c:\windows\fonts\*.ttf
# Adjust with your favorite fonts
$globalFonts = (
"arial",
"ariblk",
"BRITANIC",
"BROADW",
"calibri",
"consola",
"javatext",
"STENCIL",
"times",
"verdana",
"MonoLisa-Regular"
)


$maxFiles = 4
[string[]]$resolvedFiles = New-Object string[] $maxFiles

$resolvedCount = 0
$sharedPathValid = $false

# Use ffprobe to get each video's duration
# Originally the goal was to TPAD each video to the same length
Function Get-FileDuration {
Param([Parameter(Mandatory=$false)][string]$filePath="")
    $duration = & ffprobe -i $filePath -show_entries format=duration -v quiet -of csv="p=0"
    return $duration
}

Function Wrap-Not {
Param(
    [Parameter(Mandatory=$true)][string]$wrap,
    [Parameter(Mandatory=$true)][bool]$negate
)
    If( $negate ){
     "not($($wrap))"   
    } Else {
        $wrap
    }
}

Function Get-FFMPEGEnableEveryNSeconds {
Param(
    [Parameter(Mandatory=$true)][string]$n,
    [Parameter(Mandatory=$true)][string]$d,
    [Parameter(Mandatory=$true)][bool]$negate
)
    # TODO: enable 3 way alternation.
    "enable=" + ( Wrap-Not -wrap "lt(mod(t\,$d)\,$n)" -negate $negate )
}

Function Get-FFMPEGFontAndSize {
Param(
    [Parameter(Mandatory=$false)][string]$Font,
    [Parameter(Mandatory=$false)][int]$FontIndex,
    [Parameter(Mandatory=$true)][string]$PointSize
)
    # No Join-Path, FFMPEG beyond picky
    If( $FontIndex -ge 0 ){
        $Font = $globalFonts[$FontIndex]
    }

    "fontfile=$([string]::Concat($fontPath,"$Font.ttf")):fontsize=$PointSize"
}

Function Get-FFMPEGFontColor {
Param(
    [Parameter(Mandatory=$false)][string]$Color,
    [Parameter(Mandatory=$false)][int]$ColorIndex
)
    If( $Color ) {
        "fontcolor=$Color"   
    } ElseIf( $FontIndex -ge 0 ) {
        "fontcolor=$($globalColors[$ColorIndex])" 
    } Else {
        Write-Host "Get-FFMPEGFontColor no color found"
        Exit
    }
}

# RegEx Utility and Token Expansion

Function Get-RegexGroupVal {
Param(
    [Parameter(Mandatory=$true)][System.Text.RegularExpressions.GroupCollection]$Group,
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$false)][Type]$Type=[object]
)
    $v = $Group | Where-Object { $_.Name -eq $name } | Select -First 1 -ExpandProperty Value
    # could add Bool
    If( $Type -eq [int] ) {
        If( $v -eq "" -or $v -eq $null ) {
            $v = [int]-1
        } Else { 
            $v = $v -as [int]
        }
    }
    return $v
}

# Think this function isn't needed? The typo took longer than all the RegEx work
# Let the computer do it
Function Wrap-NonCaptureGroup {
  Param( [Parameter(Mandatory=$true)][string]$Wrap )  
  return "(?:" + $Wrap + ")" 
}

# .NET requires non capturing groups for | to remain top level
# (your regex may vary)
# Supported Tokens
$timeAlt = "_(?<negate>N?)ENABLE_(?<secnum>\d*)_(?<secdiv>\d*)_"
$fntSize = "_FONT_(?<font>[a-zA-Z]*)(?<fontindex>\d*)_(?<fontsize>\d*)_"
$fntColr = "_FC_(?<color>[a-zA-Z]*)(?<colorindex>\d*)_"

$wrpTimeAlt = Wrap-NonCaptureGroup -Wrap $timeAlt
$wrpFontSize = Wrap-NonCaptureGroup -Wrap $fntSize
$wrpFontColr = Wrap-NonCaptureGroup -Wrap $fntColr

# Set the all Token match pattern
$patternRgxCore = "$wrpFontSize|$wrpTimeAlt|$wrpFontColr"


Function Expand-VideoFilterTokens {
Param( 
    [Parameter(Mandatory=$true)][string]$VideoFilter,
    [Parameter(Mandatory=$true)][string]$FilterName
)  

    $matches = [regex]::Matches($VideoFilter, $patternRgxCore)

    $replaces = $matches | ForEach-Object {
        $matchSuccess = $_.Groups[0].Success
        $matchType = [string]$_.Groups[0].Value
        $everyNSeconds = $false
        $fontAndSize = $false
        $fontColor = $false

        $videoFilterElement = ""

        # Identify Token
        If( $matchType.StartsWith("_FONT") ) {
             $fontAndSize = $true
        } ElseIf ( $matchType.StartsWith("_FC_") ) {
             $fontColor = $true
        } Else {
            $everyNSeconds = $true
        }

        # Skip No Matches
        If( -Not $matchSuccess ) {
            Continue
        }

        If( $everyNSeconds ) {

            $neg = Get-RegexGroupVal -Group $_.Groups -Name "negate"
            $negate = $false
            If( $neg -eq 'N' ) {
                $negate = $true
            }
            $secondsNum = Get-RegexGroupVal -Group $_.Groups -Name "secnum"
            $secondsDiv = Get-RegexGroupVal -Group $_.Groups -Name "secdiv"

            $videoFilterElement = Get-FFMPEGEnableEveryNSeconds -n $secondsNum -d $secondsDiv -negate $negate

        } ElseIf( $fontAndSize ) {
    
            $fontIndex = [int]-1
            $font = Get-RegexGroupVal -Group $_.Groups -Name "font"
            [int]$fontindex = Get-RegexGroupVal -Group $_.Groups -Name "fontindex" -Type $fontIndex.GetType()
            $pointSize = Get-RegexGroupVal -Group $_.Groups -Name "fontsize"

            $videoFilterElement = Get-FFMPEGFontAndSize -Font $font -FontIndex $fontIndex -PointSize $pointSize
 
        } ElseIf( $fontColor ) {

            $colorIndex = [int]-1
            $colorName = Get-RegexGroupVal -Group $_.Groups -Name "color"
            [int]$colorIndex = Get-RegexGroupVal -Group $_.Groups -Name "colorindex" -Type $colorIndex.GetType()

            $videoFilterElement = Get-FFMPEGFontColor -Color $colorName -ColorIndex $fontIndex
 
        } Else {
            Write-Warning "No Token Found"
        }

        $token = $_.Groups[0].Value
        $tind = $_.Groups[0].Index
        $tlen = $_.Groups[0].Length
 
        return [PSCustomObject]@{ Index = [int]$tind; 
            Chars = [int]$tlen;
            Token = $token;
            VideoFilterElement=$videoFilterElement
        }
    }

    # Manual string substitution with logging, look into Replace
    $sb = [System.Text.StringBuilder]::new()
    $s = 0
    $replaces | Foreach-Object { 
        $index = $($_.Index)
        $l = $index - $s
        $re = $($_.VideoFilterElement)
        $tok = $($_.Token)
        $sb.Append( $VideoFilter.Substring( $s, $l ) ) | Out-Null
        $outLen = $sb.Length
        $sb.Append( $($_.VideoFilterElement) ) | Out-Null

        If( $Debug ) {
            Write-Verbose "Replace $FilterName $($s+$l)-$($s+$l+$tok.Length) $tok $outLen-$($outLen + $re.Length) $re"
        }
        $s = $($_.Index) + $($_.Chars)
     }
    $sb.Append( $VideoFilter.Substring($s) ) | Out-Null
    $srVft = $sb.ToString()

    Write-Verbose "Expanded $FilterName $VideoFilter"
    Write-Verbose "To $srVft"
    return $srVft
}

# Input file expansion and verification

Function Test-DosWildcard {
Param([Parameter(Mandatory=$true)][string]$filePath)

    return $filePath.IndexOfAny(('*','?')) -ne -1
}

Function Test-BaseAndFile {
Param(
    [Parameter(Mandatory=$true)][string]$notRootedFile,
    [Parameter(Mandatory=$true)][string]$verifiedBase
)
    $testFullPath = Join-Path -Path $verifiedBase -ChildPath $notRootedFile
    If( -Not (Test-Path $testFullPath) ){
        Write-Host "$fullPath not found"
        Exit
    }   
    $testFullPath
}

Function Add-VerifiedFile {
Param(
    [Parameter(Mandatory=$true)][string]$filePath,
    [Parameter(Mandatory=$true)][int]$index,
    [Parameter(Mandatory=$false)][string]$ParameterName
)
    Write-Verbose "Adding $ParameterName $index $filePath"
    $resolvedFiles[$index] = $filePath
    $index++
    $resolvedCount = $index
    If( $index -eq $maxFiles ){
        return -1
    }
    return $index
}


Function Test-FileParam {
Param(
    [Parameter(Mandatory=$true)][string]$file,
    [Parameter(Mandatory=$true)][string]$sharedBase,
    [Parameter(Mandatory=$true)][bool]$sharedPathValid,
    [Parameter(Mandatory=$true)][int]$verifiedCount,
    [Parameter(Mandatory=$true)][string]$ParameterName
)

    $testWildCardPath = ""
    $rooted = $false
    $relativeDir = ""
    $wildcard = Test-DosWildcard -filePath $file
    $newVerifiedCount = $verifiedCount
    $remainingCount = $maxFiles - $verifiedCount

    $rooted = [System.IO.Path]::IsPathRooted($file) 
    If( $wildCard ) {
   
        If( -not $rooted ){
            $relativeDir = [System.IO.Path]::GetDirectoryName($file)

            If( $sharedPathValid ){
                $file = Test-BaseAndFile -notRootedFile $file -verifiedBase $sharedBase
                $rooted = $true
            } Else {
                If( -Not (Test-Path $file) ){
                    Write-Host "$file not found"
                    Exit
                }
            }
            $rooted = $true
            # fall thru
        }

        If( $rooted ){

            $matchingItems = Get-ChildItem -Path $file -File -Recurse | 
                # Prohibit already added from matching 
                Where-Object {-Not ($resolvedFiles -contains $_.FullName)} | 
                Select -first $remainingCount

            Foreach ( $f in $matchingItems ) {
                $fullyQualfied = $f.FullName
                $newVerifiedCount = Add-VerifiedFile -filePath $fullyQualfied -index $newVerifiedCount -ParameterName $ParameterName
                If( $newVerifiedCount -eq -1 ){
                    Break
                }
            }
        }
    } Else {
        # no Wildcard chars
         If( $rooted ) {
            If( -Not (Test-Path $file) ){
                Write-Host "$file not found"
                Exit
            }
            $newVerifiedCount = Add-VerifiedFile -filePath $file -index $newVerifiedCount -ParameterName $ParameterName
         } Else {
      
            $file = Test-BaseAndFile -notRootedFile $file -verifiedBase $sharedBase
            $newVerifiedCount = Add-VerifiedFile -filePath $file -index $newVerifiedCount -ParameterName $ParameterName
        }
    }
    return $newVerifiedCount
}

# Validate Shared Path
$basePath = ""
If( $SharedPath -and (Test-Path -Path $SharedPath) ){
    $basePath = $SharedPath
    $sharedPathValid = $true
} Else {
    Write-Host "Shared Path $SharedPath defined but not found"
    Exit
}

# Parameter Processing

# F1 is always required
If( [string]::IsNullOrWhiteSpace($F1) ) { 
    Write-Host "-F1 '$F1' is required"
    Exit
}

# Add F1 - wildcard could bring in multiple
$verifiedCount = Test-FileParam -file $F1 -sharedBase $basePath -sharedPathValid $sharedPathValid -verifiedCount $verifiedCount -ParameterName "F1"
Write-Verbose "$F1 $verifiedCount"

# Loop thru F2..F4 as needed
Foreach( $loopParameter in $paramLoop ) {
    $p = $PSBoundParameters[$loopParameter]
    If( $p ){
        Write-Verbose "Testing $loopParameter $p $verifiedCount"
        $verifiedCount = Test-FileParam -file $p -sharedBase $basePath -sharedPathValid $sharedPathValid -verifiedCount $verifiedCount  -ParameterName $loopParameter
        If( $verifiedCount -ge $maxFiles ){
            Break
        }
    }
}

If( $Debug ) {
    For( $i = 0; $i -lt $resolvedFiles.Count; $i++ ) {
        $s = $resolvedFiles[$i]
        If( $s -eq $null ) {
            Write-Verbose "$i NULL"
        } else {
            Write-Verbose "$i $s"
        }
    }
}

# TODO Improve Output
$outputPath = Join-Path -Path $Output -ChildPath "gallery.mp4"


# Video Filter Template expansion
Write-Verbose "Processing Video Filter RegEx Tokens using"
Write-Verbose $patternRgxCore

$VF0 = Expand-VideoFilterTokens -VideoFilter $V0 -FilterName "V0"

$VF1 = Expand-VideoFilterTokens -VideoFilter $V1 -FilterName "V1"

$VF2 = Expand-VideoFilterTokens -VideoFilter $V2 -FilterName "V2"

$VF3 = Expand-VideoFilterTokens -VideoFilter $V3 -FilterName "V3"


# Create FilePath, Duration, Padding, TPad
$fileAndDuration = $resolvedFiles | Where-Object { $_ } | ForEach-Object { 
    $path = $_
    $duration = Get-FileDuration -filePath $path

    [PSCustomObject]@{ FilePath = $path; Duration = [float]$duration; Padding =[float]0; TPad="" }
}

# Longest File
$maxDuration = ($fileAndDuration | 
    Measure-Object -Property Duration -Maximum).Maximum

# Set the TPAD padding amount
# $($fileAndDuration[0].TPad) in [v:0]... to restore this.  :stop_mode=clone is likely best
$fileAndDuration | ForEach-Object -Begin {$i = 0} -Process { 
    $padding = $maxDuration - $_.Duration
    $_.Padding = $padding

    $color = $globalColors[0] # Black
    If( -Not ($padding -lt 2) ) {
        $color = $globalColors[$i]
    }

    $_.TPad = "tpad=stop_duration=$($_.Padding.ToString("F4")):color=$color"
    $i++
}

# Convert files to -i filePath... 
# Powershell needs each cmd line parm seperately
$fileInputs = ($resolvedFiles | Foreach-Object { Write-Output "-i"; Write-Output """$_""" } )


If( $Debug ) {

    Write-Verbose "INPUT $fileInputs"
    Write-Verbose "File Duration and Padding"

    $fileAndDuration | Foreach-Object { 
        $d = $_.Duration
        $p = $_.FilePath
        $pd = $_.Padding
        $tpad = $_.TPad
        Write-Verbose "$p $d $pd $tpad"
    }
}

#$orderedByLength = $fileAndDuration | 
#    Sort { [float]$_.Duration } -Descending | 
#    Select-Object FilePath, Duration, @{Name="Pad"; Expression={$maxDuration - $_.Duration} }


<#
FFPlay is a good way to test filters and syntax
Windows 11 PowerShell
Notice the font path, comma and quote escaping

ffplay "C:\temp\yourvideo.mp4" -vf 'scale=qvga, split[a][b]; [a]pad=iw*2:ih, drawtext=fontfile=C\\:/Windows/fonts/arial.ttf:fontsize=24:fontcolor=White:x=10:y=10:text=''%{pts\:hms} %{pict_type}'' [src];  [b]negate=enable=gt(mod(t\,10)\,5), monochrome=enable=lt(mod(t\,10)\,2), fillborders=left=38:right=38:mode=fixed:color=MediumPurple, drawtext=fontfile=C\\:/Windows/fonts/arial.ttf:fontsize=24:fontcolor=White:x=40:y=10:enable=gt(mod(t\,10)\,5):text=''%{pts\:hms} %{pict_type}'' [filt]; [src][filt]overlay=w'

https://ffmpeg.org/ffmpeg-all.html#Examples-117
qrencode=text="www.ffmpeg.org":Q=220:q=5/6*Q
graphmonitor=size="404x720":flags="all"

Filters: hflip negate vflip roberts monochrome oscilloscope dblur
 gblur seemed to take over the screen

#>

$slash = $([char]92)
$quote = $([char]34)
$colon = $([char]58)
$apos = $([char]39)
$sq = "$slash$quote"
$sa = "$slash$apos"

# this does not work, AI will likley suggest it
# DrawText expr//: can only return int, not chars.
# "%{expr\\:if( lt(mod(t\,60)\,30)\, $($sq)EdgeDetect$($sq)\, $($sq)Roberts$($sq) )}"

# eof_action not supported, repeatlast not found


# Scale, THEN choose font & pointSize, or expect to need a very large font
# Be SURE to not have a , after the filter's parameters are complete

$filterComplex = 
"[0:v] setpts=PTS-STARTPTS, scale=qvga, $VF0 [g0]; `
[1:v] setpts=PTS-STARTPTS, scale=qvga, $VF1 [g1]; `
[2:v] setpts=PTS-STARTPTS, scale=qvga, $VF2 [g2]; `
[3:v] setpts=PTS-STARTPTS, scale=qvga, $VF3 [g3]; `
[g0][g1][g2][g3]xstack=inputs=4:shortest=0:layout=0_0|0_h0|w0_0|w0_h0:[out]; `
[0:a][1:a][2:a][3:a]amix=inputs=4:duration=longest [a]" 


If( $showCommandLineOnly ) {
$ffMpegCommand =
@"
ffmpeg.exe $fileInputs
  -filter_complex $filterComplex
    -map "[out]"
    -map "[a]" -ac 2
    -c:v libx264 -preset fast -crf 23 "$outputPath" 
"@

    Write-Host "FFMpeg Command, use -report before output.mp4 for certainty"
    Write-Host $ffMpegCommand
    Exit
}

Read-Host "Press Any Key to run FFMPEG"

ffmpeg.exe $fileInputs `
  -filter_complex $filterComplex `
    -map "[out]" `
    -map "[a]" -ac 2 `
    -c:v libx264 -preset fast -crf 23 "$outputPath"

<#
Other sources
https://trac.ffmpeg.org/wiki/Create%20a%20mosaic%20out%20of%20several%20input%20videos

fmpeg -i top-left.mp4 -i top-right.mp4 -i bottom-left.mp4 -i bottom-right.mp4 -filter_complex 
"[1]tpad=start_mode=clone:start_duration=5[tr];[2]tpad=start_mode=clone:start_duration=10[bl];
    [3]tpad=start_mode=clone:start_duration=15[br];[0][tr][bl][br]
        xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0[v];[1:a]adelay=5s:all=true[a1];[2:a]adelay=10s:all=true[a2];[3:a]adelay=15s:all=true[a3];[0:a][a1][a2][a3]amix=inputs=4[a]" -map "[v]" -map "[a]" -report output.mp4

ffmpeg
    -i v_nimble_guardian.mkv 
    -i macko_nimble_guardian.mkv 
    -i ghost_nimble_guardian_subtle_arrow_1.mp4 
    -i nano_nimble_guardian.mkv
    -filter_complex "
        nullsrc=size=1920x1080 [base];
        [0:v] trim=start_pts=49117,setpts=PTS-STARTPTS, scale=960x540 [upperleft];
        [1:v] trim=start_pts=50483,setpts=PTS-STARTPTS, scale=960x540 [upperright];
        [2:v] trim=start_pts=795117,setpts=PTS-STARTPTS, scale=960x540 [lowerleft];
        [3:v] trim=start_pts=38100,setpts=PTS-STARTPTS, scale=960x540 [lowerright];
        [base][upperleft] overlay=shortest=1 [tmp1];
        [tmp1][upperright] overlay=shortest=1:x=960 [tmp2];
        [tmp2][lowerleft] overlay=shortest=1:y=540 [tmp3];
        [tmp3][lowerright] overlay=shortest=1:x=960:y=540
    "
    -c:v libx264 -report output.mkv
#>
