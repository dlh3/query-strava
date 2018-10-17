#!/bin/bash

### INITIALIZERS
mkdir ~/.querystrava &> /dev/null


### FIELDS
# QS_CLIENT_ID
# QS_CLIENT_SECRET
# QS_AUTH_TOKEN
# QS_REFRESH_TOKEN
# QS_AUTH_TOKEN_EXPIRY


### HELPERS
qs_for_each() {
	local QS_FOREACH_COMMAND=$1

	while read -r line; do
		eval $QS_FOREACH_COMMAND $line &
	done
}


### AUTH
qs_auth() {
	QS_CLIENT_ID=${1:-$QS_CLIENT_ID}
	QS_CLIENT_SECRET=${2:-$QS_CLIENT_SECRET}

	if [[ -z $QS_CLIENT_ID || -z $QS_CLIENT_SECRET ]]; then
		echo "Client ID and secret required"
		echo
		echo "Retrieve from https://www.strava.com/settings/api"
		read -p 'Client ID: ' QS_CLIENT_ID
		read -p 'Client secret: ' QS_CLIENT_SECRET
		echo
	fi

	echo "Authorize the application here: https://www.strava.com/oauth/authorize?client_id=${QS_CLIENT_ID}&redirect_uri=http://localhost:8080/site/&response_type=code&scope=read_all,activity:read_all,profile:read_all"

	local QS_AUTH_CODE
	read -p 'Code (from callback URL): ' QS_AUTH_CODE
	echo

	http POST "https://www.strava.com/oauth/token?client_id=${QS_CLIENT_ID}&client_secret=${QS_CLIENT_SECRET}&code=${QS_AUTH_CODE}&grant_type=authorization_code" \
	 | qs_parse_auth_response

	echo "Auth token: ${QS_AUTH_TOKEN}"
	echo "Refresh token: ${QS_REFRESH_TOKEN}"
	echo "Token expires: $(date -r ${QS_AUTH_TOKEN_EXPIRY})"
}

qs_touch_auth() {
	if [[ `date +%s` -gt $[QS_AUTH_TOKEN_EXPIRY - 3600] ]]; then
		http POST "https://www.strava.com/oauth/token?client_id=${QS_CLIENT_ID}&client_secret=${QS_CLIENT_SECRET}&refresh_token=${QS_REFRESH_TOKEN}&grant_type=refresh_token" \
		 | qs_parse_auth_response
	fi
}

qs_parse_auth_response() {
	local QS_AUTH_RESPONSE=$(jq '.')

	QS_AUTH_TOKEN=$(echo ${QS_AUTH_RESPONSE} | jq -r '.access_token')
	QS_REFRESH_TOKEN=$(echo ${QS_AUTH_RESPONSE} | jq -r '.refresh_token')
	QS_AUTH_TOKEN_EXPIRY=$(echo ${QS_AUTH_RESPONSE} | jq -r '.expires_at')
}


### QUERIES
qs_query_strava() {
	local QS_QUERY_URI=$1
	local QS_QUERY_METHOD=${2:-GET} # default GET
	local QS_QUERY_BASE_URL='https://www.strava.com/api/v3'

	qs_touch_auth
	local QS_RESPONSE=$(http ${QS_QUERY_METHOD} "${QS_QUERY_BASE_URL}${QS_QUERY_URI}" "Authorization:Bearer ${QS_AUTH_TOKEN}")
	echo $QS_RESPONSE  | jq '.'
}

qs_query_segments_starred() {
	local QS_QUERY_PAGE_SIZE=${1:-2} # default 2

	qs_query_strava "/segments/starred?per_page=${QS_QUERY_PAGE_SIZE}"
}

qs_query_segment_leaderboard() {
	local QS_SEGMENT_ID=$1

	qs_query_strava "/segments/${QS_SEGMENT_ID}/leaderboard"
}


### FILTERS
qs_filter_segments_with_efforts() {
	jq 'map(select(.athlete_pr_effort != null))'
}


### PROCESSORS
qs_build_segment_board() {
	local QS_SEGMENTS_INPUT=$(jq '.')

	echo > ~/.querystrava/segments.html
	echo "
	   <html>
	   <head>
		<link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/gh/christianbach/tablesorter@07e0918254df3c2057d6d8e4653a0769f1881412/themes/blue/style.css\" />

		<script type=\"text/javascript\" src=\"https://cdn.jsdelivr.net/gh/christianbach/tablesorter@07e0918254df3c2057d6d8e4653a0769f1881412/jquery-latest.js\"></script>
		<script type=\"text/javascript\" src=\"https://cdn.jsdelivr.net/gh/christianbach/tablesorter@07e0918254df3c2057d6d8e4653a0769f1881412/jquery.tablesorter.js\"></script>
		<script type=\"text/javascript\" src=\"https://cdn.jsdelivr.net/gh/christianbach/tablesorter@07e0918254df3c2057d6d8e4653a0769f1881412/jquery.metadata.js\"></script>
		<script type=\"text/javascript\">
			\$(document).ready(() => \$('.tablesorter').tablesorter({ widgets: ['zebra'] }));
		</script>
	   </head>
	   <body>
		<table class=\"tablesorter { sortlist: [[5,0]] }\">
		 <thead>
		  <tr>
		   <th>ID</th>
		   <th>Name</th>
		   <th>Rank</th>
		   <th>CR Time (MM:SS)</th>
		   <th>PR Time (MM:SS)</th>
		   <th>Delta (MM:SS)</th>
		   <th>Distance (m)</th>
		   <th>Average Grade (%)</th>
		   <th>Maximum Grade (%)</th>
		   <th>Minimum Elevation (m)</th>
		   <th>Maximum Elevation (m)</th>
		   <!-- th>Athlete PR</th -->
		 </thead>
		 <tbody>
	" >> ~/.querystrava/segments.html

	echo $QS_SEGMENTS_INPUT | jq '.[].id' | 
	while read -r segmentId; do
		local QS_SEGMENT=$(echo $QS_SEGMENTS_INPUT | jq "map(select(.id == $segmentId))")
		local QS_SEGMENT_LEADERBOARD=$(qs_query_segment_leaderboard $segmentId &)

		local QS_SEGMENT_URL="https://www.strava.com/segments/${segmentId}"
		local QS_SEGMENT_ENTRIES=$(echo $QS_SEGMENT_LEADERBOARD | jq '.entry_count')

		local QS_SEGMENT_CR=$(echo $QS_SEGMENT_LEADERBOARD | jq '.entries[0].elapsed_time')
		local QS_SEGMENT_PR=$(echo $QS_SEGMENT | jq '.[].pr_time')
		local QS_SEGMENT_CR_DELTA=$[QS_SEGMENT_PR - QS_SEGMENT_CR]

		local QS_SEGMENT_PR_START=$(echo $QS_SEGMENT | jq '.[].athlete_pr_effort.start_date')
		local QS_SEGMENT_ATHLETE_RANK=$(echo $QS_SEGMENT_LEADERBOARD | jq ".entries | map(select(.elapsed_time == ${QS_SEGMENT_PR})) | map(select(.start_date == ${QS_SEGMENT_PR_START})) | .[].rank")

		echo "
			  <tr>
			   <td><a href='${QS_SEGMENT_URL}'>${segmentId}</a></td>
			   <td><a href='${QS_SEGMENT_URL}'>$(echo $QS_SEGMENT | jq -r '.[].name')</a></td>
			   <td>${QS_SEGMENT_ATHLETE_RANK} / ${QS_SEGMENT_ENTRIES}</td>
			   <td>$(qs_seconds_to_timestamp $QS_SEGMENT_CR)</td>
			   <td>$(qs_seconds_to_timestamp $QS_SEGMENT_PR)</td>
			   <td>$(qs_seconds_to_timestamp $QS_SEGMENT_CR_DELTA)</td>
			   <td>$(echo $QS_SEGMENT | jq '.[].distance')</td>
			   <td>$(echo $QS_SEGMENT | jq '.[].average_grade')</td>
			   <td>$(echo $QS_SEGMENT | jq '.[].maximum_grade')</td>
			   <td>$(echo $QS_SEGMENT | jq '.[].elevation_low')</td>
			   <td>$(echo $QS_SEGMENT | jq '.[].elevation_high')</td>
			   <!-- td>$(echo $QS_SEGMENT | jq '.[].athlete_pr_effort')</td -->
			  </tr>
		" >> ~/.querystrava/segments.html
	done

	echo "
		 </tbody>
		</table>
	   </body>
	" >> ~/.querystrava/segments.html

	open ~/.querystrava/segments.html
}

qs_seconds_to_timestamp() {
	local QS_TIME_IN_SECONDS=$1

	printf '%d:%02d' $[QS_TIME_IN_SECONDS / 60] $[QS_TIME_IN_SECONDS % 60]
}
