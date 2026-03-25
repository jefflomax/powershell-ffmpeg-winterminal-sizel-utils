
Function List-Keyframes {
Param(
[Parameter()][string]$inputFile
)
    # -read_intervals "%+9" can skip many segments
    # ffprobe even in csv p=0 STILL emits a seperator after the 1st item
    # setting item_sep (abbr s) to '\ ' defeats this
    $r = ( & ffprobe -select_streams v -loglevel error -sexagesimal -show_entries frame=pts_time -of csv=p=0:s='\ ' -skip_frame nokey -i $inputFile )

    $timeSpans = ($r | ForEach-Object { [TimeSpan]$_ } ) 

    $timeSpans

}
