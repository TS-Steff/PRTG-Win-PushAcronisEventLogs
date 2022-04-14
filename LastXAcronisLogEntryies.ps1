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
$probeIP = "PROBE" #include https or http
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
       -URI ($probeIP + ":" + $sensorPort + "/" + $sensorKey) `
       -ContentType "text/xml" `
       -Body $prtgresult `
       -usebasicparsing
  
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
$lastEvent = Get-WinEvent -ProviderName $eventSource -MaxEvents 1

$events = Get-WinEvent -ProviderName $eventSource -MaxEvents $numLastEvents
#write-host "length: " $events.Count

$eventsCount = $events.Count-1 


#$eventsWarn = 0
$eventsSuccess = 0
$eventsAbort = 0
$eventsError = 0
$eventsUnknown = 0

$eventsWarnDates = "Warnings: "
$eventsErrDates = "Errors: "
$eventsAbortDates = "Aborts: "



#### Last Backup State ####
$lastEvent = [xml]$lastEvent[0].ToXml()
$lastEventDataLine = $lastEvent.Event.EventData.Data.Split([Environment]::NewLine)
$lastEventCode = $lastEventDataLine[0].Split(":")[2].Trim() #2 is the error code

switch ($lastEventCode){
    12      { $lastEventState = 0 } # OK
    14      { $lastEventState = 1 } # Error
    29      { $lastEventState = 2 } # Abort
    Default { $lastEventState = 9 } # Unknown
}



for($i=0; $i -ne $events.Count; $i++){
    #write-host "i: " $i
    $event = [xml]$events[$i].ToXml()
    #write-host "Level: " $event.Event.System.Level
    #write-host "Data: " $event.Event.EventData.Data
    #write-host " "

    <####
     # 1 - Ereignis mit : am schluss
     # 3 - Fehlercode
     ####>
    $eventDataLine = $event.Event.EventData.Data.Split([Environment]::NewLine)

    $eventDataErrorCode = $eventDataLine[0].Split(":")[2].Trim() #2 is the error code

    #write-host "'$eventDataErrorCode'"

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






$prtgText = ""
if($eventsError -ne 0){$prtgText += $eventsErrDates}
if($eventsAbort -ne 0){$prtgText += $eventsAbortDates}
#write-host $prtgText


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
        <LimitMaxWarning>0</LimitMaxWarning>
        <LimitWarningMsg>$eventsError warnings in the Last $numLastEvents events</LimitWarningMsg>
        <LimitMaxError>3</LimitMaxError>
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
    <result>
        <channel>Last State</channel>
        <unit>custom</unit>
        <value>$lastEventState</value>
        <valueLookup>ts.acronis.push</valueLookup>
        <showChart>1</showChart>
        <showTable>1</showTable>
    </result>
    <text>Last $numLastEvents events // $prtgText</text>
</prtg>

"@


#write-host $prtgresult

SendPush