#!/bin/bash

### INITIALIZERS
mkdir ~/.querystrava &> /dev/null


### FIELDS
QS_AUTH_CALLBACK_PORT=5744

QS_CLIENT_ID=$QS_CLIENT_ID
QS_CLIENT_SECRET=$QS_CLIENT_SECRET
QS_AUTH_TOKEN=$QS_AUTH_TOKEN
QS_REFRESH_TOKEN=$QS_REFRESH_TOKEN
QS_AUTH_TOKEN_EXPIRY=$QS_AUTH_TOKEN_EXPIRY


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

		local QS_API_SETTINGS_URL="https://www.strava.com/settings/api"
		echo "Opening browser to: ${QS_API_SETTINGS_URL}"
		open $QS_API_SETTINGS_URL
		echo

		read -p 'Client ID: ' QS_CLIENT_ID
		read -p 'Client secret: ' QS_CLIENT_SECRET
		echo
	fi


	local QS_AUTH_URL="https://www.strava.com/oauth/authorize?client_id=${QS_CLIENT_ID}&redirect_uri=http://localhost:${QS_AUTH_CALLBACK_PORT}/&response_type=code&scope=read_all,activity:read_all,profile:read_all"
	echo "Opening browser to: ${QS_AUTH_URL}"
	open $QS_AUTH_URL

	echo "Listening for callback on port ${QS_AUTH_CALLBACK_PORT}..."
	local QS_AUTH_CALLBACK_REQUEST=$(echo -e 'HTTP/1.1 200 OK\n\n<h1>Success!</h1>\n<h2>Return to console.</h2>\n' | \
										nc -l $QS_AUTH_CALLBACK_PORT | head -n1)
	local QS_AUTH_CODE=$(sed -E 's|^.+code=([^&]+)&?[^&]*$|\1|' <<< $QS_AUTH_CALLBACK_REQUEST)
	echo "Received callback: ${QS_AUTH_CALLBACK_REQUEST}"
	echo


	local QS_AUTH_RESPONSE=$(http POST "https://www.strava.com/oauth/token?client_id=${QS_CLIENT_ID}&client_secret=${QS_CLIENT_SECRET}&code=${QS_AUTH_CODE}&grant_type=authorization_code")

	QS_AUTH_TOKEN=$(jq -r '.access_token' <<< $QS_AUTH_RESPONSE)
	QS_REFRESH_TOKEN=$(jq -r '.refresh_token' <<< $QS_AUTH_RESPONSE)
	QS_AUTH_TOKEN_EXPIRY=$(jq -r '.expires_at' <<< $QS_AUTH_RESPONSE)

	echo "Auth token: ${QS_AUTH_TOKEN}"
	echo "Refresh token: ${QS_REFRESH_TOKEN}"
	echo "Token expires: $(date -r ${QS_AUTH_TOKEN_EXPIRY})"
}

qs_touch_auth() {
	if [[ `date +%s` -gt $[QS_AUTH_TOKEN_EXPIRY - 3600] ]]; then
		local QS_AUTH_RESPONSE=$(http POST "https://www.strava.com/oauth/token?client_id=${QS_CLIENT_ID}&client_secret=${QS_CLIENT_SECRET}&refresh_token=${QS_REFRESH_TOKEN}&grant_type=refresh_token")

		QS_AUTH_TOKEN=$(jq -r '.access_token' <<< $QS_AUTH_RESPONSE)
		QS_REFRESH_TOKEN=$(jq -r '.refresh_token' <<< $QS_AUTH_RESPONSE)
		QS_AUTH_TOKEN_EXPIRY=$(jq -r '.expires_at' <<< $QS_AUTH_RESPONSE)
	fi
}


### QUERIES
qs_query_strava() {
	local QS_QUERY_URI=$1
	local QS_QUERY_METHOD=${2:-GET} # default GET
	local QS_QUERY_BASE_URL='https://www.strava.com/api/v3'

	qs_touch_auth
	local QS_RESPONSE=$(http ${QS_QUERY_METHOD} "${QS_QUERY_BASE_URL}${QS_QUERY_URI}" "Authorization: Bearer ${QS_AUTH_TOKEN}")
	jq '.' <<< $QS_RESPONSE
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
		<style>
			tr span.crown {
				visibility: hidden;
			}

			tr.king span.crown {
				visibility: visible;
			}

			table.tablesorter tbody tr.king.odd td {
				background-color: limegreen;
			}

			table.tablesorter tbody tr.king.even td {
				background-color: lightgreen;
			}

			table.tablesorter tbody tr.top5.odd td {
				background-color: palegoldenrod;
			}

			table.tablesorter tbody tr.top5.even td {
				background-color: lightgoldenrodyellow;
			}

			table.tablesorter tbody tr.top10.odd td {
				background-color: lightblue;
			}

			table.tablesorter tbody tr.top10.even td {
				background-color: paleturquoise;
			}
		</style>

		<script type=\"text/javascript\" src=\"https://cdn.jsdelivr.net/gh/christianbach/tablesorter@07e0918254df3c2057d6d8e4653a0769f1881412/jquery-latest.js\"></script>
		<script type=\"text/javascript\" src=\"https://cdn.jsdelivr.net/gh/christianbach/tablesorter@07e0918254df3c2057d6d8e4653a0769f1881412/jquery.tablesorter.js\"></script>
		<script type=\"text/javascript\" src=\"https://cdn.jsdelivr.net/gh/christianbach/tablesorter@07e0918254df3c2057d6d8e4653a0769f1881412/jquery.metadata.js\"></script>
		<script type=\"text/javascript\">
			$.tablesorter.addParser({ 
				// set a unique id 
				id: 'chopSpace', 

				// return false so this parser is not auto detected 
				is: function(s) { 
					return false; 
				}, 

				// format your data for normalization 
				format: function(s) { 
					return s.replace(/ .*$/, '');
				}, 

				// set type, either numeric or text 
				type: 'numeric' 
			}); 

			$.tablesorter.addParser({ 
				// set a unique id 
				id: 'timestamp', 

				// return false so this parser is not auto detected 
				is: function(s) { 
					return false; 
				}, 

				// format your data for normalization 
				format: function(s) { 
					var parts = s.replace(/ .*$/, '').split(':');
					return (parts[0] * 60) + parts[1];
				}, 

				// set type, either numeric or text 
				type: 'numeric' 
			}); 

			\$(document).ready(() => \$('.tablesorter').tablesorter({ widgets: ['zebra'] }));
		</script>
	   </head>
	   <body>
		<table class=\"tablesorter { sortlist: [[2,0]] }\">
		 <thead>
		  <tr>
		   <th>ID</th>
		   <th>Name</th>
		   <th class=\"{ sorter: 'chopSpace' }\">Rank</th>
		   <th>Rank Impressiveness</th>
		   <th class=\"{ sorter: 'timestamp' }\">CR Time (MM:SS)</th>
		   <th class=\"{ sorter: 'timestamp' }\">PR Time (MM:SS)</th>
		   <th class=\"{ sorter: 'timestamp' }\">Delta (MM:SS)</th>
		   <th class=\"{ sorter: 'chopSpace' }\">Delta (%)</th>
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
		local QS_SEGMENT=$(jq "map(select(.id == $segmentId)) | .[0]" <<< $QS_SEGMENTS_INPUT)
		local QS_SEGMENT_LEADERBOARD=$(qs_query_segment_leaderboard $segmentId &)

		local QS_SEGMENT_URL="https://www.strava.com/segments/${segmentId}"
		local QS_SEGMENT_ENTRIES=$(jq '.entry_count' <<< $QS_SEGMENT_LEADERBOARD)

		local QS_SEGMENT_CR=$(jq '.entries[0].elapsed_time' <<< $QS_SEGMENT_LEADERBOARD)
		local QS_SEGMENT_PR=$(jq '.pr_time' <<< $QS_SEGMENT)
		local QS_SEGMENT_CR_DELTA=$[QS_SEGMENT_PR - QS_SEGMENT_CR]
		local QS_SEGMENT_CR_DELTA_PERCENTAGE=$[10000 * QS_SEGMENT_CR_DELTA / QS_SEGMENT_CR]

		local QS_SEGMENT_PR_START=$(jq '.athlete_pr_effort.start_date' <<< $QS_SEGMENT)
		local QS_SEGMENT_ATHLETE_RANK=$(jq ".entries | map(select(.elapsed_time == ${QS_SEGMENT_PR})) | .[0].rank" <<< $QS_SEGMENT_LEADERBOARD)
		local QS_SEGMENT_ATHLETE_RANK_IMPRESSIVENESS=$(bc <<< "scale=4; (1 - (${QS_SEGMENT_ATHLETE_RANK} / ${QS_SEGMENT_ENTRIES})) * 100")

		echo "
			  <tr class=\"$(qs_generate_segment_row_rank_class $QS_SEGMENT_ATHLETE_RANK)\">
			   <td><a href=\"${QS_SEGMENT_URL}\">${segmentId}</a></td>
			   <td><span class=\"crown\">👑 </span><a href=\"${QS_SEGMENT_URL}\">$(jq -r '.name' <<< $QS_SEGMENT)</a></td>
			   <td>${QS_SEGMENT_ATHLETE_RANK} / ${QS_SEGMENT_ENTRIES}</td>
			   <td>$(printf "%.2f" ${QS_SEGMENT_ATHLETE_RANK_IMPRESSIVENESS})</td>
			   <td>$(qs_seconds_to_timestamp $QS_SEGMENT_CR)</td>
			   <td>$(qs_seconds_to_timestamp $QS_SEGMENT_PR)</td>
			   <td>$(qs_seconds_to_timestamp $QS_SEGMENT_CR_DELTA) $(qs_generate_segment_delta_flames $QS_SEGMENT_CR_DELTA)</td>
			   <td>$(printf "%.2f" $(bc <<< "scale=2; ${QS_SEGMENT_CR_DELTA_PERCENTAGE} / 100")) $(qs_generate_segment_delta_percentage_flames $QS_SEGMENT_CR_DELTA_PERCENTAGE)</td>
			   <td>$(jq '.distance' <<< $QS_SEGMENT)</td>
			   <td>$(jq '.average_grade' <<< $QS_SEGMENT)</td>
			   <td>$(jq '.maximum_grade' <<< $QS_SEGMENT)</td>
			   <td>$(jq '.elevation_low' <<< $QS_SEGMENT)</td>
			   <td>$(jq '.elevation_high' <<< $QS_SEGMENT)</td>
			   <!-- $(jq '.athlete_pr_effort' <<< $QS_SEGMENT) -->
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

qs_generate_segment_row_rank_class() {
	local QS_SEGMENT_ATHLETE_RANK=$1

	if [ "$QS_SEGMENT_ATHLETE_RANK" -eq 1 ]; then
		echo "king"
	elif [ "$QS_SEGMENT_ATHLETE_RANK" -le 5 ]; then
		echo "top5"
	elif [ "$QS_SEGMENT_ATHLETE_RANK" -le 10 ]; then
		echo "top10"
	fi
}

qs_generate_segment_delta_flames() {
	local QS_SEGMENT_CR_DELTA=$1

	if [ "$QS_SEGMENT_CR_DELTA" -eq 0 ]; then
		echo ""
	elif [ "$QS_SEGMENT_CR_DELTA" -le 5 ]; then
		echo "🔥🔥🔥"
	elif [ "$QS_SEGMENT_CR_DELTA" -le 15 ]; then
		echo "🔥🔥"
	elif [ "$QS_SEGMENT_CR_DELTA" -le 30 ]; then
		echo "🔥"
	fi
}

qs_generate_segment_delta_percentage_flames() {
	local QS_SEGMENT_CR_DELTA_PERCENTAGE=$1

	if [ "$QS_SEGMENT_CR_DELTA_PERCENTAGE" -eq 0 ]; then
		echo ""
	elif [ "$QS_SEGMENT_CR_DELTA_PERCENTAGE" -le 500 ]; then
		echo "🔥🔥🔥"
	elif [ "$QS_SEGMENT_CR_DELTA_PERCENTAGE" -le 1000 ]; then
		echo "🔥🔥"
	elif [ "$QS_SEGMENT_CR_DELTA_PERCENTAGE" -le 1500 ]; then
		echo "🔥"
	fi
}
