function disableAutoReload(enabled) {
	toggleAutoReload(false);
	$('#autoReloadToggle').remove();
}

function toggleAutoReload(enabled) {
	autoReload = enabled;
	setTimeout(() => {
		if (autoReload) {
			document.location.reload();
		}
	}, 2000);
}

toggleAutoReload(true);
