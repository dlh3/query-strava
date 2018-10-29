function toggleSegmentIframe(segmentId) {
	// disable auto-reload
	toggleAutoReload(false);

	var currentRow = $('#' + segmentId);
	var iframeRow = $('#iframe-' + segmentId);

	if (iframeRow.length) {
		iframeRow[0].remove();
	} else {
		iframeRow = $('<tr id="iframe-' + segmentId + '">');
		iframeRow.append($(`
				<td onclick="toggleSegmentIframe(${segmentId})">X Close</td>
				<td colspan="99">
					<iframe height="405" width="800" frameborder="0" allowtransparency="true" scrolling="no" src="https://www.strava.com/segments/${segmentId}/embed"></iframe>
				</td>
			`));

		currentRow.after(iframeRow);
	}
}
