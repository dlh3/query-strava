var defaultTablesorterOpts = 
	{
		theme: 'blue',
		widgets: ['zebra', 'stickyHeaders'],
		sortList: [[3,0]]
	};
$(document).ready(() => $('.tablesorter').tablesorter(defaultTablesorterOpts));


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