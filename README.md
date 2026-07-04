# FFMpeg Utilities and helpers

## xstack builder
Example of how to create 2 x 2 ( 4 video ) gallery with all _**videos playing to the end**_ and all audio streams mixed and playing to the end.

Makes it easier to build FFMpeg inputs for these 2x2 gallery's.


Notice amix instead of amerge as it supports duration
```
ffmpeg.exe 
    -i "C:\temp\tv\video\testvideos1.mp4" 
    -i "C:\temp\tv\video\testvideos2.mp4" 
    -i "C:\temp\tv\video\testvideos3.mp4" 
    -i "C:\temp\tv\video\testvideos4.mp4"
  -filter_complex "[0:v] setpts=PTS-STARTPTS, scale=qvga [g0];
[1:v] setpts=PTS-STARTPTS, scale=qvga [g1];
[2:v] setpts=PTS-STARTPTS, scale=qvga [g2];
[3:v] setpts=PTS-STARTPTS, scale=qvga [g3];
[g0][g1][g2][g3]xstack=inputs=4:shortest=0:layout=0_0|0_h0|w0_0|w0_h0:[out];
[0:a][1:a][2:a][3:a]amix=inputs=4:duration=longest [a]"
    -map "[out]"
    -map "[a]" -ac 2
    -c:v libx264 -preset fast -crf 23 "c:\temp\tv\gallery.mp4"
```

Example:
```PowerShell
.\ffxstack.ps1 -SharedPath "C:\temp\tv\" -F1 "video\testvideos?.mp4" -Verbose
```

### Supports simple RegEx video filter parameter expansion
* Time Alternation Enable filter parameter
    - \_ENABLE\_30_60\_
    - \_NENABLE_30_60\_
    - These enable or disable 30 seconds for each 60 seconds
        + \_ENABLE_15_60\_ produces enable=lt(mod(t\\,60)\\,15)
        + \_NENABLE_15_60\_ produces enable=not(lt(mod(t\\,60)\\,15))
* Font and PointSize filter parameters
    - \_FONT_arial_14\_  (by name without extension)
    - \_FONT_2_14\_      (by index - set your fonts in script)
    - This expands the quite long fontfile and fontsize filter parameters
        + fontfile=C\\\\:/Windows/fonts/BRITANIC.ttf:fontsize=18
* Fontcolor filter parameter
    - \_FC_PaleGoldenRod\_ (by name)
    - \_FC_8\_             (by index - set your colors in script)

### File Input parameters F1 [SharedPath] [F2 F3 F4]
* All support DOS wildcards (* ?)
* \-F1 is required  \-F1 "C:\temp\tv\video\testvideos?.mp4"
* \-SharedPath is optional but recommended, will prepend to F1..F4 -SharedPath "C:\temp\tv\"
* \-F2 .. \-F4 are optional
* \-ShowCommandLineOnly $true will generate and display the FFMpeg command line but not run FFMpeg

### Video Filter customization
* \-V0 \-V1 \-V2 \-V3 PowerShell parameters add to each video's filters
* Example alternating V3 between edgedetect and roberts every 30 seconds with different text on each
* \-V3="edgedetect=\_ENABLE_30_60\_, roberts=\_NENABLE_30_60\_:scale=2:delta=10, drawtext=\_ENABLE_30_60\_:\_FONT_3_18\_:text='Edge Detect':\_FC_8\_:x=10:y=10, drawtext=\_NENABLE_30_60\_:\_FONT_3_20\_:text='Roberts':\_FC_8\_:x=10:y=10 "

## cut ffmpeg
* Simple example of cutting a time segment out of a video
    - .\cut-ffmpeg.ps1 \-imageFile test1.mp4 \-Seg1Start "" \-Seg1Finish "00:00:08.000" \-Seg2Start "00:00:32.500" \-Seg2Finish ""

#### Assure you have FFMpeg installed

* Setup, all free open source tools, no accounts, online, tracking or selling you.
* Run from non-Admin Windows Terminal, Installs FFMPEG 7.1 - (Gyan.FFmpeg)
   - winget install FFmpeg
   - Restart your Windows Terminal

