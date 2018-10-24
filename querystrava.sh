#!/bin/bash

### INITIALIZERS
mkdir ~/.querystrava &> /dev/null


### FIELDS
QS_AUTH_CALLBACK_PORT=5744

QS_CLIENT_ID=$QS_CLIENT_ID
QS_CLIENT_SECRET=$QS_CLIENT_SECRET
QS_AUTH_TOKEN=$QS_AUTH_TOKEN
QS_AUTH_REFRESH_TOKEN=$QS_AUTH_REFRESH_TOKEN
QS_AUTH_TOKEN_EXPIRY=$QS_AUTH_TOKEN_EXPIRY


### HELPERS
qs_for_each() {
	local QS_FOREACH_COMMAND=$1

	while read -r line; do
		eval $QS_FOREACH_COMMAND $line &
	done
}

qs_curl() {
	local QS_QUERY_METHOD=$1
	local QS_QUERY_URL=$2

	qs_log "${QS_QUERY_METHOD} ${QS_QUERY_URL}"
	curl -s -X "${QS_QUERY_METHOD}" "${QS_QUERY_URL}" -H "Authorization: Bearer ${QS_AUTH_TOKEN}"
}

qs_log() {
	echo -e "INFO: $1" 1>&2
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


	local QS_AUTH_URL="https://www.strava.com/oauth/authorize?client_id=${QS_CLIENT_ID}&redirect_uri=http://localhost:${QS_AUTH_CALLBACK_PORT}/&response_type=code&scope=read,read_all,activity:read,activity:read_all,profile:read_all"
	echo "Opening browser to: ${QS_AUTH_URL}"
	open $QS_AUTH_URL

	echo "Listening for callback on port ${QS_AUTH_CALLBACK_PORT}..."
	local QS_AUTH_CALLBACK_REQUEST=$(echo -e 'HTTP/1.1 200 OK\n\n<h1>Success!</h1>\n<h2>Return to console.</h2>\n' | \
										nc -l $QS_AUTH_CALLBACK_PORT | head -n1)
	local QS_AUTH_CODE=$(sed -E 's|^.+code=([^&]+)&?[^&]*$|\1|' <<< $QS_AUTH_CALLBACK_REQUEST)
	echo "Received callback: ${QS_AUTH_CALLBACK_REQUEST}"
	echo

	local QS_AUTH_RESPONSE=$(qs_curl POST "https://www.strava.com/oauth/token?client_id=${QS_CLIENT_ID}&client_secret=${QS_CLIENT_SECRET}&code=${QS_AUTH_CODE}&grant_type=authorization_code")
	QS_AUTH_TOKEN=$(jq -r '.access_token' <<< $QS_AUTH_RESPONSE)
	QS_AUTH_REFRESH_TOKEN=$(jq -r '.refresh_token' <<< $QS_AUTH_RESPONSE)
	QS_AUTH_TOKEN_EXPIRY=$(jq -r '.expires_at' <<< $QS_AUTH_RESPONSE)

	echo "Auth token: ${QS_AUTH_TOKEN}"
	echo "Refresh token: ${QS_AUTH_REFRESH_TOKEN}"
	echo "Token expires: $(date -r ${QS_AUTH_TOKEN_EXPIRY})"
}

qs_touch_auth() {
	if [[ `date +%s` -gt $[QS_AUTH_TOKEN_EXPIRY - 3600] ]]; then
		qs_log "Refreshing auth token"

		local QS_AUTH_RESPONSE=$(qs_curl POST "https://www.strava.com/oauth/token?client_id=${QS_CLIENT_ID}&client_secret=${QS_CLIENT_SECRET}&refresh_token=${QS_AUTH_REFRESH_TOKEN}&grant_type=refresh_token")
		QS_AUTH_TOKEN=$(jq -r '.access_token' <<< $QS_AUTH_RESPONSE)
		QS_AUTH_REFRESH_TOKEN=$(jq -r '.refresh_token' <<< $QS_AUTH_RESPONSE)
		QS_AUTH_TOKEN_EXPIRY=$(jq -r '.expires_at' <<< $QS_AUTH_RESPONSE)
	fi
}


### QUERIES
qs_query_strava() {
	local QS_QUERY_URI=$1
	local QS_QUERY_METHOD=${2:-GET} # default GET
	local QS_QUERY_BASE_URL='https://www.strava.com/api/v3'

	qs_touch_auth
	local QS_RESPONSE=$(qs_curl "${QS_QUERY_METHOD}" "${QS_QUERY_BASE_URL}${QS_QUERY_URI}")
	jq '.' <<< $QS_RESPONSE
}

qs_query_segments_starred() {
	local QS_QUERY_PAGE_SIZE=${1:-2} # default 2

	qs_query_strava "/segments/starred?per_page=${QS_QUERY_PAGE_SIZE}"
}

qs_query_segment() {
	local QS_SEGMENT_ID=$1

	qs_query_strava "/segments/${QS_SEGMENT_ID}"
}

qs_query_segment_leaderboard() {
	local QS_SEGMENT_ID=$1

	qs_query_strava "/segments/${QS_SEGMENT_ID}/leaderboard"
}

qs_query_activity() {
	local QS_ACTIVITY_ID=$1

	qs_query_strava "/activities/${QS_ACTIVITY_ID}?include_all_efforts=true"
}

qs_query_activity_ids() {
	local QS_CURRENT_PAGE=1
	local QS_RESULTS_PER_PAGE=30
	local QS_PAGE_RESULTS_NUM=-1
	local QS_ACTIVITY_IDS=()

	while [ "$QS_PAGE_RESULTS_NUM" -ne 0 ]; do
		local QS_ACTIVITIES=$(qs_query_strava "/athlete/activities?per_page=${QS_RESULTS_PER_PAGE}&page=${QS_CURRENT_PAGE}")
		QS_ACTIVITY_IDS+=($(jq '.[].id' <<< $QS_ACTIVITIES))

		QS_PAGE_RESULTS_NUM=$(jq 'length' <<< $QS_ACTIVITIES)
		QS_CURRENT_PAGE=$[QS_CURRENT_PAGE + 1]
	done

	tr ' ' '\n' <<< ${QS_ACTIVITY_IDS[@]}
}

qs_query_discovered_segments() {
	local QS_SEGMENT_IDS=()

	while read -r activityId; do
		local QS_ACTIVITY=$(qs_query_activity $activityId)
		QS_SEGMENT_IDS+=($(jq '.segment_efforts[].segment.id' <<< $QS_ACTIVITY))

		local QS_SEGMENT_EFFORTS_COUNT=$(jq '.segment_efforts | length' <<< $QS_ACTIVITY)
		qs_log "Segment efforts for activity ${activityId}: $QS_SEGMENT_EFFORTS_COUNT"
	done <<< $(qs_query_activity_ids)

	tr ' ' '\n' <<< ${QS_SEGMENT_IDS[@]} | sort -u
}


### FILTERS
qs_filter_segments_with_efforts() {
	jq 'map(select(.athlete_pr_effort != null))'
}


### PROCESSORS
qs_build_segment_board_from_segments() {
	local QS_SEGMENTS_INPUT=$(jq '.')

	jq '.[].id' <<< $QS_SEGMENTS_INPUT | qs_build_segments_board_from_ids
}

qs_build_segments_board_from_ids() {
	echo > ~/.querystrava/segments.html
	echo "
	   <html>
	   <head>
		<link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/gh/christianbach/tablesorter@07e0918254df3c2057d6d8e4653a0769f1881412/themes/blue/style.css\" />
		<style>
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
				id: 'stringLength',

				// return false so this parser is not auto detected
				is: function(s) {
					return false;
				},

				// format your data for normalization
				format: function(s) {
					return s.length;
				},

				// set type, either numeric or text
				type: 'text'
			});

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
					var multiplier = s.startsWith('-') ? -1 : 1;

					var parts = s.replace(/ .*$/, '').split(':');
					return multiplier * ((Math.abs(parts[0]) * 60) + parts[1]);
				},

				// set type, either numeric or text
				type: 'numeric'
			});

			\$(document).ready(() => \$('.tablesorter').tablesorter({ widgets: ['zebra'] }));
		</script>

		<script type=\"text/javascript\">
			function toggleSegmentIframe(segmentId) {
				var currentRow = \$('#' + segmentId);
				var iframeRow = \$('#iframe-' + segmentId);

				if (iframeRow.length) {
					iframeRow[0].remove();
				} else {
					iframeRow = \$('<tr id=\"iframe-' + segmentId + '\">');
					iframeRow.append(\$('<td onclick=\"toggleSegmentIframe(' + segmentId + ')\">X Close</td>'));
					iframeRow.append(\$('<td colspan=\"99\"><iframe height=\"405\" width=\"800\" frameborder=\"0\" allowtransparency=\"true\" scrolling=\"no\" src=\"https://www.strava.com/segments/' + segmentId + '/embed\"></iframe></td>'));

					currentRow.after(iframeRow);
				}
			}
		</script>

		<base target=\"_blank\" />
	   </head>
	   <body>
		<table class=\"tablesorter { sortlist: [[3,0]] }\">
		 <thead>
		  <tr>
		   <th>ID</th>
		   <th class=\"{ sorter: 'stringLength' }\">⭐</th>
		   <th>Name (click to expand leaderboard)</th>
		   <th class=\"{ sorter: 'chopSpace' }\">Rank</th>
		   <th>Impressiveness</th>
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

	local QS_CROWN_TOTAL=0;
	while read -r segmentId; do
 		[[ -z $segmentId ]] && continue
		unset "${!QS_SEGMENT@}"

		local QS_SEGMENT=$(qs_query_segment $segmentId)
		local QS_SEGMENT_LEADERBOARD=$(qs_query_segment_leaderboard $segmentId)

		local QS_SEGMENT_LEADERBOARD_ENTRIES=$(jq '.entries' <<< $QS_SEGMENT_LEADERBOARD)
		[[ "null" == "$QS_SEGMENT_LEADERBOARD_ENTRIES" ]] && qs_log "Error retrieving segment ${segmentId} leaderboard" && continue

		local QS_SEGMENT_URL="https://www.strava.com/segments/${segmentId}"
		local QS_SEGMENT_STAR=$([[ 'true' == `jq '.starred' <<< $QS_SEGMENT` ]] && echo ❤️)

		local QS_SEGMENT_CR=$(jq '.[0].elapsed_time' <<< $QS_SEGMENT_LEADERBOARD_ENTRIES)
		local QS_SEGMENT_PR=$(jq '.athlete_segment_stats.pr_elapsed_time' <<< $QS_SEGMENT)

		local QS_SEGMENT_ENTRIES=$(jq '.entry_count' <<< $QS_SEGMENT_LEADERBOARD)
		local QS_SEGMENT_ATHLETE_RANK=$(jq "map(select(.elapsed_time == ${QS_SEGMENT_PR})) | .[0].rank" <<< $QS_SEGMENT_LEADERBOARD_ENTRIES)
		local QS_SEGMENT_ATHLETE_RANK_IMPRESSIVENESS=$(bc <<< "scale=4; (1 - (${QS_SEGMENT_ATHLETE_RANK} / ${QS_SEGMENT_ENTRIES})) * 100")

		local QS_SEGMENT_CR_DELTA=$[QS_SEGMENT_PR - QS_SEGMENT_CR]
		if [ $QS_SEGMENT_ATHLETE_RANK -eq 1 ]; then
			QS_CROWN_TOTAL=$[QS_CROWN_TOTAL + 1]
			local QS_SEGMENT_CROWN="👑"

			local QS_SEGMENT_RUNNERUP_TIME=$(jq "map(select(.rank == 2)) | .[0].elapsed_time" <<< $QS_SEGMENT_LEADERBOARD_ENTRIES)
			local QS_SEGMENT_CR_DELTA=$[QS_SEGMENT_CR - QS_SEGMENT_RUNNERUP_TIME]
		fi
		local QS_SEGMENT_CR_DELTA_PERCENTAGE=$[10000 * QS_SEGMENT_CR_DELTA / QS_SEGMENT_CR]

		echo "
			  <tr id=\"${segmentId}\" class=\"$(qs_generate_segment_row_rank_class $QS_SEGMENT_ATHLETE_RANK)\">
			   <td><a href=\"${QS_SEGMENT_URL}\">${segmentId}</a></td>
			   <td>${QS_SEGMENT_STAR}</td>
			   <td onclick=\"toggleSegmentIframe(${segmentId})\">$(jq -r '.name' <<< $QS_SEGMENT) ${QS_SEGMENT_CROWN}</td>
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
	done <<< "$(</dev/stdin)"

	echo "
		 </tbody>
		</table>
		<script type=\"text/javascript\">
			\$('head').append(\$('<title>👑 ${QS_CROWN_TOTAL} 👑</title>'));
		</script>
	   </body>
	" >> ~/.querystrava/segments.html

	open ~/.querystrava/segments.html
}

qs_seconds_to_timestamp() {
	local QS_TIME_IN_SECONDS=$1

	local QS_NEGATIVE_TIME=''
	if [ "$QS_TIME_IN_SECONDS" -lt 0 ]; then
		QS_TIME_IN_SECONDS=$[QS_TIME_IN_SECONDS * -1]
		QS_NEGATIVE_TIME='-'
	fi

	printf "%s%d:%02d" "$QS_NEGATIVE_TIME" $[QS_TIME_IN_SECONDS / 60] $[QS_TIME_IN_SECONDS % 60]
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

	if [ "$QS_SEGMENT_CR_DELTA" -le 0 ]; then
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

	if [ "$QS_SEGMENT_CR_DELTA_PERCENTAGE" -le 0 ]; then
		echo ""
	elif [ "$QS_SEGMENT_CR_DELTA_PERCENTAGE" -le 500 ]; then
		echo "🔥🔥🔥"
	elif [ "$QS_SEGMENT_CR_DELTA_PERCENTAGE" -le 1000 ]; then
		echo "🔥🔥"
	elif [ "$QS_SEGMENT_CR_DELTA_PERCENTAGE" -le 1500 ]; then
		echo "🔥"
	fi
}
