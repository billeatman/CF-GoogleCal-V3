<cfcomponent output="false" accessors="false">

<cfset variables.oauth2 = "">
<cfset variables.baseAPIEndpoint = "">
<cfset variables.redirects = 5> <!--- number of times to try redirects --->

<cffunction name="init" access="public" output="false" hint="The constructor method.">
	<cfargument name="oauth2" type="ANY" required="true" hint="oauth2 object">
	<!--- https://www.googleapis.com/calendar/v3 --->
	<cfargument name="baseAPIEndpoint"	type="string" required="false" default="https://www.googleapis.com/calendar/v3" hint="The base URL to which we will make the API requests." />

	<cfset variables.baseAPIEndpoint = arguments.baseAPIEndpoint>
	<cfset variables.oauth2 = arguments.oauth2> 

	<cfreturn this>
</cffunction>

<cffunction name="Calendars" access="public">
	<cfreturn new calendars(gc: this)>
</cffunction>

<cffunction name="MakeRequest" access="private" returntype="struct" output="false" hint="Make API Request to Google.">
	<cfargument name="method" required="true" type="string" hint="post, get, etc">
	<cfargument name="url" required="true" type="string" hint="prefixes baseAPIEndpoint if no http">
	<cfargument name="body" required="false" type="string" hint="form key / value pair">
	<cfargument name="header" required="false" type="struct" hint="extra headers"> 

	<cfset local.authSubToken = 'Bearer ' & variables.oauth2.getAccess_token() />
	
	<cfif FindNoCase("http", arguments.url, 1) EQ 0>
		<cfset local.curl = variables.baseAPIEndpoint & arguments.url>
	<cfelse>
		<cfset local.curl = arguments.url>	
	</cfif> 

	<cfif ucase(trim(arguments.method)) EQ "PATCH">
		<cfset local.method = "POST">
	<cfelse>
		<cfset local.method = arguments.method>
	</cfif>

	<!--- make request to google --->
    <cfset LOCAL.r = 0>
    <cfloop condition="LOCAL.r EQ 0 OR (LOCAL.resultStatus EQ 302 AND LOCAL.r LT variables.redirects)">
        <cfhttp url="#LOCAL.curl#" method="#local.method#" result="local.result" redirect="false">
			<cfhttpparam name="Authorization" type="header" value="#authSubToken#">

			<cfif ucase(trim(arguments.method)) EQ "PATCH">
				<cfhttpparam type="header" name="X-HTTP-Method-Override" value="PATCH">					
			</cfif> 
			
			<!--- Add JSON body content --->
			<cfif NOT isNull(arguments.body)>
				<cfif isJson(arguments.body)>					
					<cfhttpparam type="header" name="Content-Type" value="application/json">
				</cfif>				
				<cfhttpparam type="body" value="#arguments.body#">
			</cfif>

			<!--- Add extra header items --->
			<cfif structKeyExists(arguments, "header")>
				<cfloop collection="#arguments.header#" item="local.item">
					<cfhttpparam type="header" name="#local.item#" value="#structFind(arguments.header, local.item)#">
				</cfloop>
			</cfif>
        </cfhttp>

        <cfset LOCAL.r = LOCAL.r + 1>
        <cfif StructKeyExists(LOCAL.result.responseheader, 'location')>
            <cfset LOCAL.curl = LOCAL.result.responseheader.location>
        </cfif>
        <cfset LOCAL.resultStatus = LOCAL.result.responseheader.status_code>
    </cfloop>

    <cfreturn local.result>
		
</cffunction>

<cffunction name="FileContentToQuery" access="private" returntype="ANY" output="false" hint="converts the filecontent struct returned by the Google API into a query">
	<cfargument name="fileContent" type="struct" required="true" hint="FileContent struct returned from Google API">


	<cfif NOT structKeyExists(arguments.fileContent, "items")>
		<cfset local.firstStruct = arguments.fileContent>
	<cfelseif structKeyExists(arguments.fileContent, "defaultReminders")>
		<cfset local.firstStruct = arguments.fileContent>
	<cfelse>			
		<cfset local.firstStruct = arguments.fileContent.items[1]>
	</cfif>

	<cfset local.queryCols = StructKeyList(local.firstStruct, ',')>
	<cfset local.queryColsTemp = "">

	<!--- check that the list only contains simple values --->
	<cfloop list="#local.queryCols#" index=local.i>
		<cfif isSimpleValue(local.firstStruct['#local.i#'])>
			<cfset local.queryColsTemp = ListAppend(local.queryColsTemp, local.i, ',')>
		</cfif>	
	</cfloop>

	<cfset local.queryCols = local.queryColsTemp>

	<cfset local.qCals = queryNew(local.queryCols)>

	<cfif NOT structKeyExists(arguments.fileContent, "items")>
		<cfset queryAddRow(local.qCals)>
		<cfloop collection="#fileContent#" item="local.key">
	       	<cftry>
	       	<cfset querySetCell(local.qCals, local.key, fileContent[local.key])>
	       	<cfcatch>
	       	</cfcatch>
	       	</cftry>
		</cfloop>
	<cfelse>	
		<cfloop array="#fileContent.items#" index=local.i>		
			<cfset queryAddRow(local.qCals)>
			<cfloop collection="#local.i#" item="local.key">
		       	<cftry>	       		
		       	<cfset querySetCell(local.qCals, local.key, local.i[local.key])>
	        	<cfcatch>
	        		<cfif isSimpleValue(local.i[local.key])>
	        			<!--- add a column --->
	        			<cfset queryAddColumn(local.qCals, local.key, arrayNew(1))>
				       	<cfset querySetCell(local.qCals, local.key, local.i[local.key])>
	        		</cfif>
	        	</cfcatch>
	        	</cftry>
	        </cfloop>
		</cfloop> 
	</cfif>

	<cfreturn local.qCals>

</cffunction>

<cffunction name="HandleResponse" access="private" returntype="ANY" output="false">
	<cfargument name="result" type="struct" required="true">
	<cfargument name="error" type="error" required="true"> 
	<cfargument name="resultType" type="string" required="false" default="query">

	<cfset local.e = arguments.error>
    <cfset local.resultType = lcase(trim(arguments.resultType))>
	<cfset local.result = arguments.result>
	<cfset local.ret = "">

	<cfif listFind("200,201,204", LOCAL.result.responseheader.status_code, ",") EQ 0>
    	<cfset local.e.setError(message: "Error: #LOCAL.result.responseheader.status_code# #LOCAL.result.responseheader.explanation#")>
    	<cftry>    
        <cfset local.ret = deserializeJSON(LOCAL.result.fileContent)> 
    	<cfif structKeyExists(local.ret, 'error')>
    		<cfset local.e.setError(message: local.ret.error.code & ' - ' & local.ret.error.message)>
    	</cfif>
    	<cfcatch>
    		<!--- <cfset local.e.setError(message: "Not JSON response")> --->
    	</cfcatch>
    	</cftry>
    </cfif>

    <cfif NOT local.e.isError() AND listFind("filecontent,query", local.resultType) GT 0>
    	<cftry>    
        <cfset local.ret = deserializeJSON(LOCAL.result.fileContent)> 
    	<cfif structKeyExists(local.ret, 'error')>
    		<cfset local.e.setError(message: local.ret.message)>
    	</cfif>
    	<cfcatch>
    		<cfset local.e.setError(message: "Not JSON response")>
    	</cfcatch>
    	</cftry>
    <cfelseIf local.resultType EQ 'raw'>
        <cfset local.ret = LOCAL.result>
    </cfif>

    <cfif NOT local.e.isError() AND local.resultType EQ 'query' AND isStruct(local.ret)>
    	<cfset local.ret = FileContentToQuery(local.ret)>
    </cfif>

	<cfif LOCAL.e.isError() EQ true AND local.resultType NEQ 'raw'>			 
		<cfset local.e.throw()>
    <cfelse>							 
    	<cfreturn local.ret>
    </cfif>
</cffunction>

<!--- Thanks Ben! - http://www.bennadel.com/blog/2501-Converting-ColdFusion-Date-Time-Values-Into-ISO-8601-Time-Strings.htm --->
<cffunction name="GetISO8601" access="private" returntype="string">
	<cfargument name="date" type="date" required="true">  
	<cfargument name="convertToUTC" type="boolean" required="false" default="false">

	<cfset local.date = arguments.date>

	<cfif arguments.convertToUTC>
		<cfset local.date = dateConvert("local2utc", local.date)>
	</cfif>

	<cfset local.date = dateFormat( date, "yyyy-mm-dd" ) & "T" & timeFormat( date, "HH:mm:ss" )>

    <cfif arguments.convertToUTC>
        <cfset local.date = local.date & "Z">        
    </cfif>

    <!---
    https://developers.google.com/google-apps/calendar/concepts

    2011-06-03T10:00:00 — no milliseconds and no offset.
    2011-06-03T10:00:00.000 — no offset.
    2011-06-03T10:00:00-07:00 — no milliseconds with a numerical offset.
    2011-06-03T10:00:00Z — no milliseconds with an offset set to 00:00.
    2011-06-03T10:00:00.000-07:00 — with milliseconds and a numerical offset.
    2011-06-03T10:00:00.000Z — with milliseconds and an offset set to 00:00.
    --->

	<cfreturn local.date>
</cffunction>

<cffunction name="GetAllCalendars" access="public" returnType="ANY" output="false" hint="Returns all the calendars.">
    <cfargument name="resultType" default="query" type="string" required="false" hint="query, fileContent, raw">

    <cfreturn GetCalendar(argumentCollection: arguments)>
</cffunction>

<cffunction name="GetCalendar" access="public" returnType="ANY" output="false" hint="Returns all the calendars.">
    <cfargument name="calendarId" default="" type="string" required="false" hint="ID of a calendar to get">
    <cfargument name="resultType" default="query" type="string" required="false" hint="query, fileContent, raw">

    <cfset local.e = new error()>
    <cfset local.ret = false>

    <cfset local.curl = "/users/me/calendarList">
    <cfif arguments.calendarId NEQ "">
        <cfset local.curl = local.curl & "/" & urlEncodedFormat(arguments.calendarId)>
    </cfif>

    <cfset local.result = MakeRequest(url: local.curl, method: 'GET')>

    <cfreturn HandleResponse(result: local.result, error: local.e, resultType: arguments.resultType)>
</cffunction>

<cffunction name="CreateCalendar" access="public" returntype="any" output="false" hint="Creates a secondary calendar">
	<cfargument name="summary" default="" type="string" required="true" hint="Title of the calendar.">
    <cfargument name="description" required="false" hint="Description of the calendar.">
    <cfargument name="location" required="false" hint="Geographic location of the calendar as free-form text.">
    <cfargument name="timeZone" required="false" hint="The time zone of the calendar.">
    <cfargument name="resultType" default="query" type="string" required="false" hint="query, fileContent, raw">

    <cfset local.e = new error()>
    <cfset local.ret = false>

    <cfset local.curl = "/calendars">

    <cfset local.body["summary"] = arguments.summary>	

    <cfif structKeyExists(arguments, "description")>
	    <cfset local.body["description"] = arguments.description>	
    </cfif>

    <cfif structKeyExists(arguments, "location")>
	    <cfset local.body["location"] = arguments.location>	
    </cfif>

    <cfif structKeyExists(arguments, "timeZone")>
	    <cfset local.body["timeZone"] = arguments.timeZone>	
    </cfif>

    <cfset local.body = SerializeJSON(local.body)>
<!---
    <cfloop list="description,location,timeZone" index="local.item">
	    <cfif structKeyExists(arguments, local.item)>
		    <cfset local.form["#local.item#"] = structFindKey(arguments, local.item)>	
	    </cfif>
    </cfloop>
--->
    <cfset local.result = MakeRequest(url: local.curl, method: 'POST', body: local.body)>

    <cfreturn HandleResponse(result: local.result, error: local.e, resultType: arguments.resultType)>
</cffunction>

<cffunction name="getAllEvents" access="public" returnType="any" output="false" hint="Gets events.">
    <cfargument name="calendarId" type="string" required="true" hint="Calendar ID">
    <cfargument name="resultType" type="string" default="query" required="false" hint="specify which type of result set is returned (options: query, filecontent, and raw)">

	<cfreturn getEvents(argumentCollection: arguments)>
</cffunction>

<!---
<cfset local.rawEvents = getEvents(
	calendarId: arguments.calendarId, 
	resultType: 'raw')>
--->

<cffunction name="getEvents" access="public" returnType="any" output="false" hint="Returns events on the specified calendar">
    <cfargument name="calendarId" type="string" required="true" hint="Calendar ID">
    <cfargument name="resultType" type="string" default="query" required="false" hint="specify which type of result set is returned (options: query, filecontent, and raw)">
    <cfargument name="maxResults" type="numeric" required="false" hint="Max number of events. Google will default to 250">
<!---    <cfargument name="futureEvents" type="boolean" required="false" hint="Show only future events"> --->
    <cfargument name="orderBy" type="string" required="false" hint="Can be lastmodified (default) or starttime">
<!---    <cfargument name="sortdir" type="string" required="false" hint="ascending or descending"> --->
    <cfargument name="timeMin" type="date" required="false" hint="Earliest date to return.">
    <cfargument name="timeMax" type="date" required="false" hint="Latest date to return.">
    <cfargument name="singleEvents" type="boolean" required="false" hint="Expand Recurring events.">
    <cfargument name="q" type="string" required="false" hint="Simple keyword for search.">

    <cfset local.e = new error()>
    <cfset local.ret = false>

    <cfset local.curl = "/calendars/" & urlEncodedFormat(arguments.calendarId) & "/events">

    <cfset local.curl = local.curl & "?z=z">

    <cfif structKeyExists(arguments, "maxResults")>
    	<cfset LOCAL.curl = LOCAL.curl & "&maxResults=#arguments.maxResults#">
    </cfif>

	<cfif structKeyExists(arguments, "orderBy")>
    	<cfset LOCAL.curl = LOCAL.curl & "&orderby=#arguments.orderby#">
    </cfif>
    
	<cfif structKeyExists(arguments, "timeMin")>
    	<cfset LOCAL.curl = LOCAL.curl & "&timeMin=" & getISO8601(arguments.timeMin)>
    </cfif>
    
	<cfif structKeyExists(arguments, "timeMax")>
    	<cfset LOCAL.curl = LOCAL.curl & "&timeMax=" & getISO8601(arguments.timeMax)>
    </cfif>

	<cfif structKeyExists(arguments, "singleEvents")>
    	<cfset LOCAL.curl = LOCAL.curl & "&singleEvents=#arguments.singleEvents#">
    </cfif>
    
	<cfif structKeyExists(arguments, "q")>
    	<cfset LOCAL.curl = LOCAL.curl & "&q=#urlEncodedFormat(arguments.q)#">
    </cfif>

    <cfset local.curl = replaceNoCase(local.curl, "z=z&", "", "one")>

    <cfset local.result = MakeRequest(url: local.curl, method: 'GET')>

    <cfreturn HandleResponse(result: local.result, error: local.e, resultType: arguments.resultType)>
</cffunction>

<cffunction name="GetEvent" access="public" returntype="any" output="false" hint="Returns an event">
	<cfargument name="calendarId" type="string" required="true" hint="Calendar identifier">
	<cfargument name="eventId" type="string" required="true" hint="Event identifier">
    <cfargument name="resultType" type="string" default="query" required="false" hint="specify which type of result set is returned (options: query, filecontent, and raw)">

    <cfset local.e = new error()>
    <cfset local.ret = false>

    <cfset local.curl = "/calendars/" & urlEncodedFormat(arguments.calendarId) 
    	& "/events/" & urlEncodedFormat(arguments.eventId)>

    <cfset local.result = MakeRequest(url: local.curl, method: 'GET')>

    <cfreturn HandleResponse(result: local.result, error: local.e, resultType: arguments.resultType)>
</cffunction>

<cffunction name="RemoveCalendar" access="public" returntype="void" hint="Deletes a secondary calendar">
	<cfargument name="calendarId" type="string" required="true" hint="Calendar identifier">
    <cfargument name="resultType" type="string" default="none" required="false" hint="specify which type of result set is returned (options: none and raw)">

    <cfset local.e = new error()>
    <cfset local.ret = false>
 	<cfset local.resultType = lcase(trim(arguments.resultType))>
    <cfif listfind("none,raw", local.resultType, ",") EQ 0>
    	<cfset local.e.throw(message: "Invalid resultType.  Allowed types (default) none and raw")>
    </cfif>

    <cfset local.curl = "/calendars/" & urlEncodedFormat(arguments.calendarId)>

    <cfset local.result = MakeRequest(url: local.curl, method: 'DELETE')>

    <cfset HandleResponse(result: local.result, error: local.e, resultType: "none")>		
</cffunction>

<cffunction name="UpdateCalendar" access="public" returntype="any" output="false" hint="Creates a secondary calendar">
	<cfargument name="summary" type="string" required="false" hint="Title of the calendar.">
    <cfargument name="description" required="false" hint="Description of the calendar.">
    <cfargument name="location" required="false" hint="Geographic location of the calendar as free-form text.">
    <cfargument name="timeZone" required="false" hint="The time zone of the calendar.">
    <cfargument name="etag" required="false" type="string" hint="ETag String for doing a partial patch">
    <cfargument name="resultType" required="false" default="query" type="string" hint="query, fileContent, raw">

    <cfset local.e = new error()>
    <cfset local.ret = false>

	<cfset local.curl = "/calendars/" & urlEncodedFormat(arguments.calendarId)>

	<!--- Create Body --->    
    <cfset local.body = structNew()>

    <cfif structKeyExists(arguments, "summary")>
	    <cfset local.body["summary"] = arguments.summary>	
    </cfif>

    <cfif structKeyExists(arguments, "description")>
	    <cfset local.body["description"] = arguments.description>	
    </cfif>

    <cfif structKeyExists(arguments, "location")>
	    <cfset local.body["location"] = arguments.location>	
    </cfif>

    <cfif structKeyExists(arguments, "timeZone")>
	    <cfset local.body["timeZone"] = arguments.timeZone>	
    </cfif>

	<cfset ValidateCalendar(argumentCollection: arguments)>

	<cfif structKeyExists(arguments, "etag")>
	<!--- Partial patch update --->
		<cfset local.body["etag"] = arguments.etag>

		<!--- Create header --->
		<cfset local.header = structNew()>
		<cfset local.header["If-Match"] = "*"> <!--- arguments.etag> --->

	    <cfset local.body = SerializeJSON(local.body)>
	    <cfset local.result = MakeRequest(url: local.curl, method: 'PATCH', body: local.body, header: local.header)>
	<cfelse>
	<!--- full update --->
	    <cfset local.body = SerializeJSON(local.body)>
	    <cfset local.result = MakeRequest(url: local.curl, method: 'PUT', body: local.body)>
	</cfif>

    <cfreturn HandleResponse(result: local.result, error: local.e, resultType: arguments.resultType)>
</cffunction>

<cffunction name="ValidateCalendar" access="private" returntype="void" hint="throws errors if input does not validate">
	<cfargument name="timezone" type="string" required="false" hint="Long format time zone ID, Example: America/Chicago or UTC">

	<cfset local.e = new error()>

 	<!--- check tzlong --->
    <cfif structKeyExists(arguments, "timezone") AND ucase(arguments.timezone) NEQ "UTC">    
        <cfinvoke component="tzData" method="getTzData" returnvariable="LOCAL.qTZ">    
        
        <cfquery dbtype="query" name="LOCAL.qTZcheck">
            select TZ from [LOCAL].qTZ
            where TZ = <cfqueryparam cfsqltype="cf_sql_varchar" value="#arguments.timezone#">
        </cfquery>

        <cfif LOCAL.qTZcheck.recordCount NEQ 1>
            <cfset LOCAL.e.throw("Error: Invalid Long TZ (hint: Use tzData.cfc to get a list of valid TZs)")>
        </cfif>   
	</cfif>
</cffunction>

<cffunction name="RemoveEvent" access="public" returntype="void" hint="Deletes a secondary calendar">
	<cfargument name="calendarId" type="string" required="true" hint="Calendar identifier">
    <cfargument name="eventId" type="string" default="none" required="false" hint="specify which type of result set is returned (options: none and raw)">
    <cfargument name="resultType" required="false" default="none" type="string" hint="none, raw">

    <cfset local.e = new error()>
    <cfset local.ret = false>
 	<cfset local.resultType = lcase(trim(arguments.resultType))>
    <cfif listfind("none,raw", local.resultType, ",") EQ 0>
    	<cfset local.e.throw(message: "Invalid resultType.  Allowed types (default) none and raw")>
    </cfif>

    <cfset local.curl = "/calendars/" & urlEncodedFormat(arguments.calendarId) & "/events/" & arguments.eventId>

    <cfset local.result = MakeRequest(url: local.curl, method: 'DELETE')>

    <cfset HandleResponse(result: local.result, error: local.e, resultType: "none")>		
</cffunction>

<cffunction name="removeAllEvents" access="public" output="false" returntype="void">
	<cfargument name="calendarId" type="string" required="true" hint="Calendar identifier">
    <cfargument name="resultType" required="false" default="none" type="string" hint="none">

    <cfset local.e = new error()>

    <cfset local.curl = "/calendars/" & urlEncodedFormat(arguments.calendarId) & "/clear">
    <cfset local.result = MakeRequest(url: local.curl, method: 'POST')>

    <cfset HandleResponse(result: local.result, error: local.e, resultType: "none")>        
</cffunction>

<cffunction name="ValidateEvent" access="private" returntype="void">
    <cfreturn ValidateCalendar(arguments: argumentCollection)>
</cffunction>

<cffunction name="CreateEvent" access="public" returnType="any" output="false" hint="Adds an event. Returns Success or another message.">
	<cfargument name="calendarId" type="string" required="true" hint="Calendar identifier">
    <cfargument name="summary" type="string" required="true">
	<cfargument name="description" type="string" required="false">
	<cfargument name="start" type="date" required="true">
	<cfargument name="end" type="date" required="true">
	<cfargument name="location" type="string" required="false">
	<cfargument name="creator" type="struct" required="false">
    <cfargument name="timeZone" type="string" required="false" default="UTC">
    <cfargument name="resultType" required="false" default="query" type="string" hint="query, fileContent, raw">

	<cfset ValidateCalendar(argumentCollection: arguments)>

    <cfset local.e = new error()>
    <cfset local.ret = false>

	<cfset local.curl = "/calendars/" & urlEncodedFormat(arguments.calendarId) & "/events">

	<!--- Create Body --->    
    <cfset local.body = structNew()>

    <!--- Required Fields --->
    <cfset local.body["start"] = {
    	'dateTime': GetISO8601(arguments.start),
    	'timeZone': arguments.timeZone
    }>	
    
    <cfset local.body["end"] = {
    	'dateTime': GetISO8601(arguments.end),
    	'timeZone': arguments.timeZone
    }>

    <cfif structKeyExists(arguments, "summary")>
	    <cfset local.body["summary"] = arguments.summary>	
    </cfif>

    <cfif structKeyExists(arguments, "description")>
	    <cfset local.body["description"] = arguments.description>	
    </cfif>

    <cfif structKeyExists(arguments, "location")>
	    <cfset local.body["location"] = arguments.location>	
    </cfif>

    <cfif structKeyExists(arguments, "creator")>
	    <cfset local.body["creator"] = arguments.creator>	
    </cfif>

    <cfset ValidateCalendar(argumentCollection: arguments)>

    <cfset local.body = SerializeJSON(local.body)>
    <cfset local.result = MakeRequest(url: local.curl, method: 'POST', body: local.body)>

    <cfreturn HandleResponse(result: local.result, error: local.e, resultType: arguments.resultType)>

</cffunction>




</cfcomponent>