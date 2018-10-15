# QueryStrava

This is basic CLI support for interacting with the Strava API.  This tool was initially built to aid in constructing a personal segments board for identifying segments which you may be able to achieve the CR/KOM for.

The initial version of this is pretty rough, simply being a script which is sourced into a shell to expose a collection of functions.

### Prerequisites

Depends on [HTTPie](https://httpie.org/) and [jq](https://stedolan.github.io/jq/).  These are available with homebrew.

```
brew install http
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

Retrieve from https://www.strava.com/settings/api
Client ID: <prompts for client ID>
Client secret: <prompts for client secret>

Login here: https://www.strava.com/oauth/authorize?client_id=<client ID>&redirect_uri=http://localhost/&response_type=code&scope=view_private
Code (from callback URL): <prompts for code>

Auth token set as ad45ffd8d0368dc90ef751c20130f8b26fce3777

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
