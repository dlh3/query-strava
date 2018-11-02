function toggleSegmentIframe(segmentId) {
	// disable auto-reload
	toggleAutoReload(false);

	var currentRow = $('#segmentRow-' + segmentId);
	var expansionRow = $('#expansionRow-' + segmentId);
	var effortsTable = $('#segmentEfforts-' + segmentId);
	var segmentIframe = $('#segmentIframe-' + segmentId);;

	currentRow.after(expansionRow);
	expansionRow.toggleClass('hidden');

	if (!expansionRow.hasClass('initialized')) {
		// initialize tablesorter
		effortsTable.tablesorter();

		// convert ISO8601 dates to nicer format; do this after initializing tablesort (so it can sort timestamps)
		effortsTable.find('.isoDate').each((i, e) => {
			var date = new Date(e.innerText * 1000);
			e.innerText = date.toDateString() + ' @ ' + date.toLocaleTimeString();
		});

		// copy the src data attribute to set the iframe src (prevents loading all iframes on page load)
		segmentIframe.attr('src', segmentIframe.data('src'));

		// mark this expansion row as initialized
		expansionRow.addClass('initialized');
	}
}
