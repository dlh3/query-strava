#!/bin/bash

### INITIALIZERS
rm ~/.querystrava/querystrava.log &> /dev/null

mkdir ~/.querystrava &> /dev/null
touch ~/.querystrava/apiclient.sh
touch ~/.querystrava/setauth.sh

. ~/.querystrava/apiclient.sh
. ~/.querystrava/setauth.sh

OIFS="$IFS"
IFS=' '


### LOGGING
QS_LOG_LEVEL_TRACE=0
QS_LOG_LEVEL_DEBUG=1
QS_LOG_LEVEL_INFO=2
QS_LOG_LEVEL_WARN=3
QS_LOG_LEVEL_ERROR=4
QS_LOG_LEVELS=(TRACE DEBUG INFO WARN ERROR)

QS_LOG_LEVEL_DEFAULT=$QS_LOG_LEVEL_INFO


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

	. ~/.querystrava/setauth.sh
	qs_log "${QS_QUERY_METHOD} ${QS_QUERY_URL}" $QS_LOG_LEVEL_DEBUG
	curl -s -X "${QS_QUERY_METHOD}" "${QS_QUERY_URL}" -H "Authorization: Bearer ${QS_AUTH_TOKEN}" | jq . | tee -a ~/.querystrava/querystrava.log
}

qs_log() {
	local QS_LOG_STATEMENT_LEVEL=${2:-$QS_LOG_LEVEL_DEFAULT}

	local QS_LOG_STATEMENT="${QS_LOG_LEVELS[$QS_LOG_STATEMENT_LEVEL]}: $1"
	echo -e "$QS_LOG_STATEMENT" >> ~/.querystrava/querystrava.log

	if [[ $QS_LOG_STATEMENT_LEVEL -ge $QS_LOG_LEVEL_DEFAULT ]]; then
		echo -e "$QS_LOG_STATEMENT" 1>&2
	fi
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

		echo "
QS_CLIENT_ID=$QS_CLIENT_ID
QS_CLIENT_SECRET=$QS_CLIENT_SECRET
		" > ~/.querystrava/apiclient.sh
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

	qs_set_auth <<< "$(qs_curl POST "https://www.strava.com/oauth/token?client_id=${QS_CLIENT_ID}&client_secret=${QS_CLIENT_SECRET}&code=${QS_AUTH_CODE}&grant_type=authorization_code")"
}

qs_touch_auth() {
	. ~/.querystrava/setauth.sh
	if [[ -z "$QS_AUTH_TOKEN_EXPIRY" || `date +%s` > $[QS_AUTH_TOKEN_EXPIRY - 3600] ]]; then
		qs_log "Refreshing auth token"

		qs_set_auth <<< "$(qs_curl POST "https://www.strava.com/oauth/token?client_id=${QS_CLIENT_ID}&client_secret=${QS_CLIENT_SECRET}&refresh_token=${QS_AUTH_REFRESH_TOKEN}&grant_type=refresh_token")"
	fi
}

qs_set_auth() {
	local QS_AUTH_RESPONSE="$(</dev/stdin)"

	qs_log "$(tee ~/.querystrava/setauth.sh <<< "
QS_AUTH_TOKEN=$(jq -r '.access_token' <<< $QS_AUTH_RESPONSE)
QS_AUTH_REFRESH_TOKEN=$(jq -r '.refresh_token' <<< $QS_AUTH_RESPONSE)
QS_AUTH_TOKEN_EXPIRY=$(jq -r '.expires_at' <<< $QS_AUTH_RESPONSE)
	")"
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

	qs_query_strava "/segments/${QS_SEGMENT_ID}/leaderboard?context_entries=0&per_page=5"
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

	qs_log "Retrieving activities for current user"
	while [ "$QS_PAGE_RESULTS_NUM" -ne 0 ]; do
		local QS_ACTIVITIES=$(qs_query_strava "/athlete/activities?per_page=${QS_RESULTS_PER_PAGE}&page=${QS_CURRENT_PAGE}")
		QS_ACTIVITY_IDS+=($(jq '.[].id' <<< $QS_ACTIVITIES))

		QS_PAGE_RESULTS_NUM=$(jq 'length' <<< $QS_ACTIVITIES)
		QS_CURRENT_PAGE=$[QS_CURRENT_PAGE + 1]
	done
	qs_log "Collected $(tr ' ' '\n' <<< $QS_ACTIVITY_IDS[@] | wc -l | xargs) activities"

	echo "${QS_ACTIVITY_IDS[@]}"
}

qs_query_discovered_segments() {
	local QS_SEGMENT_IDS=()

	while read -r activityId; do
		local QS_ACTIVITY=$(qs_query_activity $activityId)
		QS_SEGMENT_IDS+=($(jq '.segment_efforts[].segment.id' <<< $QS_ACTIVITY))

		local QS_SEGMENT_EFFORTS_COUNT=$(jq '.segment_efforts | length' <<< $QS_ACTIVITY)
		qs_log "Collected ${QS_SEGMENT_EFFORTS_COUNT} segment efforts for activity ${activityId}"
	done <<< $(qs_query_activity_ids)

	local QS_SEGMENT_IDS_UNIQ=$(tr ' ' '\n' <<< ${QS_SEGMENT_IDS[@]} | sort -u)
	qs_log "Collected $(wc -l <<< $QS_SEGMENT_IDS_UNIQ | xargs) unique discovered segments"
	echo "$QS_SEGMENT_IDS_UNIQ"
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

qs_build_segment_board_from_ids() {
	echo > ~/.querystrava/segments.html
	echo "
	   <html>
	   <head>
	    <title>Building Segment Board...</title>

	    <link rel=\"icon shortcut-icon\" href=\"data:image/png;base64,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\" type=\"image/png\">

		<link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/gh/christianbach/tablesorter@07e0918254df3c2057d6d8e4653a0769f1881412/themes/blue/style.css\" />
		<style>
			span.nobreak {
				display: block;
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
			function substringBeforeSpace(s) {
				return s.replace(/ .*$/s, '');
			}

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
				id: 'substringBeforeSpace',

				// return false so this parser is not auto detected
				is: function(s) {
					return false;
				},

				// format your data for normalization
				format: function(s) {
					return substringBeforeSpace(s);
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

					var parts = substringBeforeSpace(s).split(':');
					return multiplier * ((multiplier * parts[0] * 60) + parts[1]);
				},

				// set type, either numeric or text
				type: 'numeric'
			});

			\$(document).ready(() => \$('.tablesorter').tablesorter({ widgets: ['zebra'] }));
		</script>

		<script type=\"text/javascript\">
			function toggleSegmentIframe(segmentId) {
				// disable auto-reload
				toggleAutoReload(false);

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

		<script>
			function toggleAutoReload(enabled) {
				autoReload = enabled;
				setTimeout(() => {
					if (autoReload) {
						document.location.reload();
					}
				}, 2000);
			}

			toggleAutoReload(true);
		</script>

		<base target=\"_blank\" />
	   </head>
	   <body>
	    <a id=\"autoReloadToggle\" href=\"#\" onclick=\"toggleAutoReload(!autoReload); return false\">Toggle auto reload</a>
		<table class=\"tablesorter { sortlist: [[3,0]] }\">
		 <thead>
		  <tr>
		   <th>ID</th>
		   <th class=\"{ sorter: 'stringLength' }\">⭐</th>
		   <th>Name (click to expand leaderboard)</th>
		   <th class=\"{ sorter: 'substringBeforeSpace' }\">Rank</th>
		   <th>💪 (%)</th>
		   <th class=\"{ sorter: 'timestamp' }\">CR Time (MM:SS)</th>
		   <th class=\"{ sorter: 'timestamp' }\">PR Time (MM:SS)</th>
		   <th class=\"{ sorter: 'timestamp' }\">Delta (MM:SS)</th>
		   <th class=\"{ sorter: 'substringBeforeSpace' }\">Delta (%)</th>
		   <th>Distance (m)</th>
		   <th>Average Grade (%)</th>
		   <th>Maximum Grade (%)</th>
		   <th>Minimum Elevation (m)</th>
		   <th>Maximum Elevation (m)</th>
		 </thead>
		 <tbody>
	" >> ~/.querystrava/segments.html

	local QS_CROWN_TOTAL=0;
	while read -r segmentId; do
		unset "${!QS_SEGMENT@}"
		[[ -z $segmentId ]] && continue
		qs_log "Processing segment ${segmentId}"

		local QS_SEGMENT=$(qs_query_segment $segmentId)
		local QS_SEGMENT_LEADERBOARD=$(qs_query_segment_leaderboard $segmentId)

		local QS_SEGMENT_LEADERBOARD_ENTRIES=$(jq '.entries' <<< $QS_SEGMENT_LEADERBOARD)
		[[ "$QS_SEGMENT_LEADERBOARD_ENTRIES" == "null" ]] && qs_log "Error retrieving segment ${segmentId} leaderboard" $QS_LOG_LEVEL_ERROR && continue

		local QS_SEGMENT_URL="https://www.strava.com/segments/${segmentId}"
		local QS_SEGMENT_STAR=$([[ 'true' == `jq '.starred' <<< $QS_SEGMENT` ]] && echo ❤️)

		local QS_SEGMENT_CR=$(jq '.[0].elapsed_time' <<< $QS_SEGMENT_LEADERBOARD_ENTRIES)
		local QS_SEGMENT_PR=$(jq '.athlete_segment_stats.pr_elapsed_time' <<< $QS_SEGMENT)

		local QS_SEGMENT_ENTRIES=$(jq '.entry_count' <<< $QS_SEGMENT_LEADERBOARD)
		local QS_SEGMENT_ATHLETE_RANK=$(jq "map(select(.elapsed_time == ${QS_SEGMENT_PR})) | .[0].rank" <<< $QS_SEGMENT_LEADERBOARD_ENTRIES)
		local QS_SEGMENT_ATHLETE_RANK_IMPRESSIVENESS=$(bc <<< "scale=4; (1 - (${QS_SEGMENT_ATHLETE_RANK} / ${QS_SEGMENT_ENTRIES})) * 100")

		local QS_SEGMENT_CR_DELTA=$[QS_SEGMENT_PR - QS_SEGMENT_CR]
		if [ "$QS_SEGMENT_ATHLETE_RANK" -eq 1 ]; then
			local QS_CROWN_TOTAL=$[QS_CROWN_TOTAL + 1]
			local QS_SEGMENT_CROWN="👑"

			local QS_SEGMENT_RUNNERUP_TIME=$(jq "map(select(.rank == 2)) | .[0].elapsed_time" <<< $QS_SEGMENT_LEADERBOARD_ENTRIES)
			local QS_SEGMENT_CR_DELTA=$[QS_SEGMENT_CR - QS_SEGMENT_RUNNERUP_TIME]
			if [[ "$QS_SEGMENT_CR_DELTA" == "$QS_SEGMENT_CR" ]]; then
				local QS_SEGMENT_CR_DELTA=0
				local QS_SEGMENT_NEGATIVE_DELTA="-"
			fi
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
			   <td>$(printf "%s%.2f" "$QS_SEGMENT_NEGATIVE_DELTA" $(bc <<< "scale=2; ${QS_SEGMENT_CR_DELTA_PERCENTAGE} / 100")) $(qs_generate_segment_delta_percentage_flames $QS_SEGMENT_CR_DELTA_PERCENTAGE)</td>
			   <td>$(jq '.distance' <<< $QS_SEGMENT)</td>
			   <td>$(jq '.average_grade' <<< $QS_SEGMENT)</td>
			   <td>$(jq '.maximum_grade' <<< $QS_SEGMENT)</td>
			   <td>$(jq '.elevation_low' <<< $QS_SEGMENT)</td>
			   <td>$(jq '.elevation_high' <<< $QS_SEGMENT)</td>
			  </tr>
		" >> ~/.querystrava/segments.html
	done <<< "$(</dev/stdin)"

	echo "
		 </tbody>
		</table>
		<script type=\"text/javascript\">
			toggleAutoReload(false);
			\$('#autoReloadToggle').remove();
		</script>
		<script type=\"text/javascript\">
			function setCrownCount(count) {
				document.title = count + ' CRs';

				var counterOffsetX = (count < 10 ? 18 : (count < 100 ? 6 : -6));

				var canvas = \$('<canvas height=\"84\" width=\"64\">')[0];
				var ctx = canvas.getContext('2d');
				ctx.font = '50px serif';
				ctx.fillText('👑', 7, 44);
				ctx.fillText(count, counterOffsetX, 84);

				\$('link[rel~=\"icon\"]')[0].href = canvas.toDataURL();
			}

			setCrownCount(${QS_CROWN_TOTAL});
		</script>
	   </body>
	" >> ~/.querystrava/segments.html

	open ~/.querystrava/segments.html
}

qs_seconds_to_timestamp() {
	local QS_TIME_IN_SECONDS=$1

	local QS_NEGATIVE_TIME=''
	if [ "$QS_TIME_IN_SECONDS" -le 0 ]; then
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

	echo "<span class=\"nobreak flames\">"
	if [ "$QS_SEGMENT_CR_DELTA" -le 0 ]; then
		echo ""
	elif [ "$QS_SEGMENT_CR_DELTA" -le 10 ]; then
		echo "🔥🔥🔥"
	elif [ "$QS_SEGMENT_CR_DELTA" -le 20 ]; then
		echo "🔥🔥"
	elif [ "$QS_SEGMENT_CR_DELTA" -le 30 ]; then
		echo "🔥"
	fi
	echo "</span>"
}

qs_generate_segment_delta_percentage_flames() {
	local QS_SEGMENT_CR_DELTA_PERCENTAGE=$1

	echo "<span class=\"nobreak flames\">"
	if [ "$QS_SEGMENT_CR_DELTA_PERCENTAGE" -le 0 ]; then
		echo ""
	elif [ "$QS_SEGMENT_CR_DELTA_PERCENTAGE" -le 750 ]; then
		echo "🔥🔥🔥"
	elif [ "$QS_SEGMENT_CR_DELTA_PERCENTAGE" -le 1500 ]; then
		echo "🔥🔥"
	elif [ "$QS_SEGMENT_CR_DELTA_PERCENTAGE" -le 2500 ]; then
		echo "🔥"
	fi
	echo "</span>"
}
