$.tablesorter.defaults.theme = 'blue';
$.tablesorter.defaults.widgets = ['zebra', 'filter', 'resizable', 'stickyHeaders'];

$(document).ready(() => {
	$('.tablesorter#segmentBoard').tablesorter();

	// Collapsible rows should never be filtered out
	$('.tablesorter').bind('filterEnd', () => $('.collapsible').removeClass('filtered'));

	// Keep collapsible rows with their parent when sorting
	$('.tablesorter').bind('sortEnd', () => {
		$('.collapsible:visible').each((i, e) => {
			var collapsibleRowId = e.id;
			var segmentRowId = collapsibleRowId.replace(/^[^-]*-/, 'segmentRow-');
			$('#' + segmentRowId).after($('#' + collapsibleRowId));
		});
	});
});
