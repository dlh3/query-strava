# QueryStrava

This is basic CLI support for interacting with the Strava API.  This tool was initially built to aid in constructing a personal segments board for identifying segments which you may be able to achieve the CR/KOM for.

The initial version of this is pretty rough, simply being a script which is sourced into a shell to expose a collection of functions.

### Prerequisites

Depends on [jq](https://stedolan.github.io/jq/).  This is available with homebrew.

```
brew install jq
```

### Installing

Just source the shell script!

```
. querystrava.sh
```

## Usage

Start by authenticating to the Strava API.  The `qs_auth` function will prompt for your account's client ID and secret, then print a login URL.  Open that URL in your browser and login to Strava.  After authorizing the application, the browser will be directed to a (probably invalid) localhost URL.  That URL will include a code, which `qs_auth` will prompt for.  Once the code is entered, the application will retrieve an auth token for use by future calls.

```
# Begin by authenticating...
$ qs_auth
Client ID and secret required

Opening browser to: https://www.strava.com/settings/api

Client ID: <prompts for client ID>
Client secret: <prompts for client ID>

Opening browser to: https://www.strava.com/oauth/authorize?client_id=<client-id>&redirect_uri=http://localhost:5744/&response_type=code&scope=read,read_all,activity:read,activity:read_all,profile:read_all
Listening for callback on port 5744...
Received callback: GET /?state=&code=49be4a9e9ba7a8811e99c50c9eb6a200156e5c35&scope=read,read_all,activity:read,activity:read_all,profile:read_all HTTP/1.1

Auth token: fe228c92d5733787138da7efa2ff68d6b7d9cbbe
Refresh token: d57d043797424da7ed5aab1dc592f85ee1c8af31
Token expires: Sun 21 Oct 2018 17:34:56 PDT
# If you need to re-authenticate, the client ID and secret will be saved, since those shouldn't change
#  If you do need to change the client ID and secret, provide them as arguments to qs_auth
$ qs_auth <client ID> <client secret>
```

In general, usage begins with a query function, which is piped to filters/getters/processors.  For more information, check [querystrava.sh](https://github.com/dlh3/query-strava/blob/master/querystrava.sh).

```
# Query for up to 50 (default 2, max 200) starred segments
#  filter out segments with no personal efforts
#   then build and open the HTML table
$ qs_query_segments_starred 50 | qs_filter_segments_with_efforts | qs_build_segment_board
```

## Contributing

Contributions are than welcome.

## Authors

* **Dave Hughes** - *Initial work* - [dlh3](https://github.com/dlh3)

## License

TBD

## Acknowledgments

* All those who came before me, and all those who follow.
