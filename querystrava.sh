#!/bin/bash

### INITIALIZERS
rm ~/.querystrava/querystrava.log &> /dev/null
rm -r ~/.querystrava/webfiles &> /dev/null

mkdir ~/.querystrava &> /dev/null
touch ~/.querystrava/apiclient.sh
touch ~/.querystrava/setauth.sh
cp -r "$(realpath "$(dirname "$BASH_SOURCE")")/webfiles" ~/.querystrava/

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

qs_pluralize() {
	local QS_PLURALIZATION_COUNT=$1
	local QS_PLURALIZATION_SINGULAR=$2
	local QS_PLURALIZATION_PLURAL=${3:-"${QS_PLURALIZATION_SINGULAR}s"}

	if [[ $QS_PLURALIZATION_COUNT == 1 ]]; then
		echo "$QS_PLURALIZATION_SINGULAR"
	else
		echo "$QS_PLURALIZATION_PLURAL"
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
	while [[ $QS_PAGE_RESULTS_NUM != 0 ]]; do
		local QS_ACTIVITIES=$(qs_query_strava "/athlete/activities?per_page=${QS_RESULTS_PER_PAGE}&page=${QS_CURRENT_PAGE}")
		QS_ACTIVITY_IDS+=($(jq '.[].id' <<< $QS_ACTIVITIES))

		QS_PAGE_RESULTS_NUM=$(jq 'length' <<< $QS_ACTIVITIES)
		QS_CURRENT_PAGE=$[QS_CURRENT_PAGE + 1]
	done
	local QS_ACTIVITY_IDS_COUNT=$(tr ' ' '\n' <<< $QS_ACTIVITY_IDS[@] | wc -l | xargs)
	qs_log "Collected $QS_ACTIVITY_IDS_COUNT $(qs_pluralize $QS_ACTIVITY_IDS_COUNT activity activities)"

	echo "${QS_ACTIVITY_IDS[@]}"
}

qs_query_discovered_segments() {
	local QS_SEGMENT_IDS=()

	while read -r activityId; do
		local QS_ACTIVITY=$(qs_query_activity $activityId)
		QS_SEGMENT_IDS+=($(jq '.segment_efforts[].segment.id' <<< $QS_ACTIVITY))

		local QS_SEGMENT_EFFORTS_COUNT=$(jq '.segment_efforts | length' <<< $QS_ACTIVITY)
		qs_log "Collected ${QS_SEGMENT_EFFORTS_COUNT} segment $(qs_pluralize $QS_SEGMENT_EFFORTS_COUNT effort) for activity ${activityId}"
	done <<< $(qs_query_activity_ids)

	local QS_SEGMENT_IDS_UNIQ=$(tr ' ' '\n' <<< ${QS_SEGMENT_IDS[@]} | sort -u)
	local QS_SEGMENT_IDS_COUNT=$(wc -l <<< $QS_SEGMENT_IDS_UNIQ | xargs)
	qs_log "Discovered $QS_SEGMENT_IDS_COUNT unique $(qs_pluralize $QS_SEGMENT_IDS_COUNT segment)"
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
	    <link rel=\"shortcut icon\" href=\"./webfiles/images/favicon.png\" type=\"image/png\">

		<link rel=\"stylesheet\" href=\"./webfiles/css/vendor/theme.blue.css\" />
		<link rel=\"stylesheet\" href=\"./webfiles/css/segmentboard.css\" />

		<script type=\"text/javascript\" src=\"./webfiles/js/vendor/jquery-3.3.1.js\"></script>
		<script type=\"text/javascript\" src=\"./webfiles/js/vendor/jquery.tablesorter.js\"></script>
		<script type=\"text/javascript\" src=\"./webfiles/js/vendor/jquery.tablesorter.widgets.js\"></script>

		<script type=\"text/javascript\" src=\"./webfiles/js/tablesorter-init.js\"></script>
		<script type=\"text/javascript\" src=\"./webfiles/js/segments-expansion.js\"></script>
		<script type=\"text/javascript\" src=\"./webfiles/js/segments-favicon.js\"></script>
		<script type=\"text/javascript\" src=\"./webfiles/js/autoreload.js\"></script>

		<base target=\"_blank\" />
	   </head>
	   <body>
	    <a id=\"autoReloadToggle\" href=\"#\" onclick=\"toggleAutoReload(!autoReload); return false\">Toggle auto reload</a>
		<table class=\"tablesorter\">
		 <thead>
		  <tr>
		   <th>ID</th>
		   <th data-sorter=\"stringLength\">⭐</th>
		   <th>Name (click to expand leaderboard)</th>
		   <th data-sorter=\"substringBeforeSpace\">Rank</th>
		   <th data-sorter=\"percent\">💪<br />(%)</th>
		   <th data-sorter=\"timestamp\">CR Time<br />(MM:SS)</th>
		   <th data-sorter=\"timestamp\">PR Time<br />(MM:SS)</th>
		   <th data-sorter=\"timestamp\">Delta<br />(MM:SS)</th>
		   <th data-sorter=\"substringBeforeSpace\">Delta<br />(%)</th>
		   <th>Distance<br />(m)</th>
		   <th data-sorter=\"percent\">Average Grade<br />(%)</th>
		   <th data-sorter=\"percent\">Maximum Grade<br />(%)</th>
		   <th>Minimum Elevation<br />(m)</th>
		   <th>Maximum Elevation<br />(m)</th>
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
			disableAutoReload();
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
	if [ "$QS_SEGMENT_CR_DELTA" -le -30 ]; then
		echo "👌👌👌"
	elif [ "$QS_SEGMENT_CR_DELTA" -le -20 ]; then
		echo "👌👌"
	elif [ "$QS_SEGMENT_CR_DELTA" -le -10 ]; then
		echo "👌"
	elif [ "$QS_SEGMENT_CR_DELTA" -le 0 ]; then
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
	if [ "$QS_SEGMENT_CR_DELTA_PERCENTAGE" -le -2500 ]; then
		echo "👌👌👌"
	elif [ "$QS_SEGMENT_CR_DELTA_PERCENTAGE" -le -1500 ]; then
		echo "👌👌"
	elif [ "$QS_SEGMENT_CR_DELTA_PERCENTAGE" -le -750 ]; then
		echo "👌"
	elif [ "$QS_SEGMENT_CR_DELTA_PERCENTAGE" -le 0 ]; then
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
