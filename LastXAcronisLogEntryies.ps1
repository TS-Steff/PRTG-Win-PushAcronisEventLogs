<#

.NOTES
┌─────────────────────────────────────────────────────────────────────────────────────────────┐ 
│ ORIGIN STORY                                                                                │ 
├─────────────────────────────────────────────────────────────────────────────────────────────┤ 
│   DATE        : 2021.08.02                                                                  |
│   AUTHOR      : TS-Management GmbH, Stefan Müller                                           | 
│   DESCRIPTION : Push Acronis Eventlog entry to PRTG                                         |
|   NOTE        : This is still in progress. We do not capture any events execpt              |
|                 SUCCESS, ABORT, ERROR                                                       |
|                 All other events are captured as unknown                                    |
└─────────────────────────────────────────────────────────────────────────────────────────────┘
#>

####
# CONFIG START
####
$probeIP = "PROBE"
$sensorPort = "PORT"
$sensorKey ="KEY"

$numLastEvents = 10
$eventSource = "Acronis Backup and Recovery"

####
# CONFIG END
####


####
# XML Header
####
$prtgresult = @"
<?xml version="1.0" encoding="UTF-8" ?>
<prtg>

"@

function sendPush(){
    Add-Type -AssemblyName system.web

    #write-host "result"-ForegroundColor Green
    #write-host $prtgresult 

    #$Answer = Invoke-WebRequest -Uri $NETXNUA -Method Post -Body $RequestBody -ContentType $ContentType -UseBasicParsing
    $answer = Invoke-WebRequest `
       -method POST `
       -URI ("http://" + $probeIP + ":" + $sensorPort + "/" + $sensorKey) `
       -ContentType "text/xml" `
       -Body $prtgresult `
       -usebasicparsing

       #-Body ("content="+[System.Web.HttpUtility]::UrlEncode.($prtgresult)) `
    #http://prtg.ts-man.ch:5055/637D334C-DCD5-49E3-94CA-CE12ABB184C3?content=<prtg><result><channel>MyChannel</channel><value>10</value></result><text>this%20is%20a%20message</text></prtg>   
    if ($answer.statuscode -ne 200) {
       write-warning "Request to PRTG failed"
       write-host "answer: " $answer.statuscode
       exit 1
    }
    else {
       $answer.content
    }
}


# Get the Last Event from Log
#$events = Get-EventLog -LogName Application -Newest $numLastEvents  -Source $eventSource

<####
 # 0 - LogAlways
 # 1 - Critical
 # 2 - Error
 # 3 - Warning
 # 4 - Informational
 # 5 - Verbose
 ####>
$events = Get-WinEvent -ProviderName $eventSource -MaxEvents $numLastEvents

#$eventsWarn = 0
$eventsSuccess = 0
$eventsAbort = 0
$eventsError = 0
$eventsUnknown = 0

$eventsWarnDates = "Warnings: "
$eventsErrDates = "Errors: "
$eventsAbortDates = "Aborts: "


for($i=0; $i -ne $events.Count; $i++){
    $event = [xml]$events[$i].ToXml()

    <####
     # 1 - Ereignis mit : am schluss
     # 3 - Fehlercode
     ####>
    $eventDataLine = $event.Event.EventData.Data.Split([Environment]::NewLine)

    $eventDataErrorCode = $eventDataLine[0].Split(":")[2].Trim() #2 is the error code

    switch ($eventDataErrorCode){
        12      { $eventsSuccess++  }

        14      { $eventsError++ 
                  $eventsErrDates += $event.Event.System.TimeCreated.SystemTime
                  $eventsErrDates += " | " }

        29      { $eventsAbort++ 
                  $eventsAbortDates += $event.Event.System.TimeCreated.SystemTime
                  $eventsAbortDates += " | " }
        
        Default { $eventsUnknown++ }
    }
}


write-host "Success: " $eventsSuccess
write-host "Abort: " $eventsAbort
write-host "Error: " $eventsError
write-host "Unknown: " $eventsUnknown

#write-host $eventsWarnDates
write-host $eventsErrDates
write-host $eventsAbortDates


$prtgText = ""
if($eventsError -ne 0){$prtgText += $eventsErrDates}
if($eventsAbort -ne 0){$prtgText += $eventsAbortDates}


####
# XML Content
#### 
$prtgresult += @"
    <result>
        <channel>Success</channel>
        <unit>Custom</unit>
        <value>$eventsSuccess</value>
        <showChart>1</showChart>
        <showTable>1</showTable>
    </result>
    <result>
        <channel>Aborts</channel>
        <unit>Custom</unit>
        <value>$eventsAbort</value>
        <showChart>1</showChart>
        <showTable>1</showTable>
        <LimitMaxWarning>2</LimitMaxWarning>
        <LimitWarningMsg>$eventsAbort warnings in the Last $numLastEvents events</LimitWarningMsg>
        <LimitMaxError>3</LimitMaxError>
        <LimitErrorMsg>$eventsAbort warnings in the Last $numLastEvents events</LimitErrorMsg>
        <LimitMode>1</LimitMode>
    </result>
    <result>
        <channel>Errors</channel>
        <unit>Custom</unit>
        <value>$eventsError</value>
        <showChart>1</showChart>
        <showTable>1</showTable>
        <LimitMaxError>1</LimitMaxError>
        <LimitErrorMsg>$eventsError errors in the last $numLastEvents events</LimitErrorMsg>
        <LimitMode>1</LimitMode>
    </result>
    <result>
        <channel>Unknown</channel>
        <unit>Custom</unit>
        <value>$eventsUnknown</value>
        <showChart>1</showChart>
        <showTable>1</showTable>
        <LimitMaxError>1</LimitMaxError>
        <LimitErrorMsg>$eventsUnknown unknown events in the last $numLastEvents events</LimitErrorMsg>
        <LimitMode>1</LimitMode>
    </result>
    <text>Last $numLastEvents events // $prtgText</text>
</prtg>

"@


#write-host $prtgresult

sendPush

