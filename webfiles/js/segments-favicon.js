function setCrownCount(count) {
	document.title = count + ' CRs';

	var counterOffsetX = (count < 10 ? 18 : (count < 100 ? 6 : -6));

	var canvas = $('<canvas height="84" width="64">')[0];
	var ctx = canvas.getContext('2d');
	ctx.font = '50px serif';
	ctx.fillText('👑', 7, 44);
	ctx.fillText(count, counterOffsetX, 84);

	$('link[rel~="icon"]')[0].href = canvas.toDataURL();
}
