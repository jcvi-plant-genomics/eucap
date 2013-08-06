$(document).ready(function() {

$('img.rounded').one('load',function () {
	var img = $(this);
	var img_width = img.width();
	var img_height = img.height();
	
	// build wrapper
	var wrapper = $('<div class="rounded_wrapper"></div>');
	wrapper.width(img_width);
	wrapper.height(img_height);
	
	// move CSS properties from img to wrapper
	wrapper.css('float', img.css('float'));
	img.css('float', 'none')
	
	wrapper.css('margin-right', img.css('margin-right'));
	img.css('margin-right', '0')

	wrapper.css('margin-left', img.css('margin-left'));
	img.css('margin-left', '0')

	wrapper.css('margin-bottom', img.css('margin-bottom'));
	img.css('margin-bottom', '0')

	wrapper.css('margin-top', img.css('margin-top'));
	img.css('margin-top', '0')

	wrapper.css('display', 'block');
	img.css('display', 'block')

	// IE6 fix (when image height or width is odd)
	if ($.browser.msie && $.browser.version == '6.0')
	{
		if(img_width % 2 != 0)
		{
			wrapper.addClass('ie6_width')
		}
		if(img_height % 2 != 0)
		{
			wrapper.addClass('ie6_height')			
		}
	}

	// wrap image
	img.wrap(wrapper);
	
	// add rounded corners
	img.after('<div class="tl"></div>');
	img.after('<div class="tr"></div>');
	img.after('<div class="bl"></div>');
	img.after('<div class="br"></div>');
}).each(function(){
	if(this.complete) $(this).trigger("load");
});
	
});
