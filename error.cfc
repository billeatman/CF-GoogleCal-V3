<cfcomponent output="false">

<cfset variables.error = false>
<cfset variables.message = "">

<cffunction name="init" returntype="error">
	<cfreturn this>
</cffunction>

<cffunction name="setError" returntype="void">
	<cfargument name="message" type="string" required="true">

	<cfset variables.error = true>
	<cfset variables.message = arguments.message>
</cffunction>

<cffunction name="throw">
	<cfargument name="message" type="string" required="false" default="">

	<cfif arguments.message NEQ "">
		<cfset setError(arguments.message)>
	</cfif>

	<cfif variables.error EQ true>
		<cfthrow message="#variables.message#">
	</cfif>
</cffunction>

<cffunction name="isError" returntype="boolean">
	<cfreturn variables.error>
</cffunction>

<cffunction name="clearError" returntype="void">
	<cfset variables.error = false>
	<cfset variables.message = "">
</cffunction>

</cfcomponent>