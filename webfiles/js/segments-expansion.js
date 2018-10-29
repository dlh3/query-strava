function toggleSegmentIframe(segmentId) {
	// disable auto-reload
	toggleAutoReload(false);

	var currentRow = $('#segmentRow-' + segmentId);
	var expansionRow = $('#expansionRow-' + segmentId);
	var effortsTable = $('#segmentEfforts-' + segmentId);
	var segmentIframe = $('#segmentIframe-' + segmentId);;

	currentRow.after(expansionRow);
	expansionRow.toggleClass('hidden');

	effortsTable.tablesorter(defaultTablesorterOpts);
	segmentIframe.attr('src', segmentIframe.data('src'));
}
