<cfcomponent output="false">

<cfset variables.error = false>
<cfset variables.message = "">
<cfset variables.detail = "">

<cffunction name="init" returntype="error">
	<cfreturn this>
</cffunction>

<cffunction name="setError" returntype="void">
	<cfargument name="message" type="string" required="true">
	<cfargument name="detail" type="string" required="false" default="">

	<cfset variables.error = true>
	<cfset variables.message = arguments.message>
	<cfset variables.detail = arguments.detail>

</cffunction>

<cffunction name="throw">
	<cfargument name="message" type="string" required="false" default="">
	<cfargument name="detail" type="string" required="false" default="">

	<cfif arguments.message NEQ "">
		<cfset variables.message = arguments.message>
	</cfif>

	<cfif arguments.detail NEQ "">
		<cfset variables.detail = arguments.detail>
	</cfif>

	<cfif variables.message eq "">
		<cfthrow message="Error - a message is required for errors">
	</cfif>

	<cfthrow message="#variables.message#" detail="#variables.detail#">
</cffunction>

<cffunction name="isError" returntype="boolean">
	<cfreturn variables.error>
</cffunction>

<cffunction name="clearError" returntype="void">
	<cfset variables.error = false>
	<cfset variables.message = "">
	<cfset variables.detail = "">
</cffunction>

</cfcomponent>