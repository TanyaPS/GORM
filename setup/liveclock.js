///////////////////////////////////////////////////////////
// "Live Clock" script - Version 2.6
// By Mark Plachetta (astroboy@zip.com.au)
//
// Get the latest version from:
// http://www.zip.com.au/~astroboy/liveclock/
//
// Based on the original script: "Upper Corner Live Clock"
// available at:
// - Dynamic Drive (http://www.dynamicdrive.com)
// - Website Abstraction (http://www.wsabstract.com)
// ========================================================
// CHANGES TO ORIGINAL SCRIPT:
// - Gave more flexibility in positioning of clock
// - Added date construct
// - User configurable
// ========================================================
// This script is available free of charge, see the website
// for more information. Please check the website before
// e-mailing for help.
///////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////
/////////////// CONFIGURATION /////////////////////////////

	// Set the clock's font face:
	var LC_Font_Face = "Arial";

	// Set the clock's font size (in point):
	var LC_Font_Size = "10";

	// Set the clock's font color:
	//var LC_Font_Color = "#FFFF99";
	var LC_Font_Color = "#000000";
	
	// Set the clock's background color:
	//var LC_Back_Color = "#0000FF";
	var LC_Back_Color = "#FFFFFF";

	// Set any extra HTML to go either side the clock here:
	var LC_OpenTags = "Time(GMT) / Date: ";
	var LC_CloseTags = " ";

	// Set the width of the clock (in pixels):
	var LC_Width = 300;

	// Display the time in 24 or 12 hour time?
	// 0 = 24, 1 = 12
	var LC_12_Hour = 0;

	// How often do you want the clock updated?
	// 0 = Never, 1 = Every Second, 2 = Every Minute
	// If you pick 0 or 2, the seconds will not be displayed
	var LC_Update = 1;

	// Date Options:
	// 0 = No Date, 1 = dd/mm/yy, 2 = mm/dd/yy, 3 = DDDD MMMM, 4 = DDDD MMMM YYYY
	var LC_DisplayDate = 1;

	// Abbreviate Day/Month names?
	// 0 = No, 1 = Yes;
	var LC_Abbrev = 0;

	// Your GMT Offset:
	// This will allow the clock to always be set to your local
	// time, rather than that of the visitor's system clock.
	// Set to "" to disable this feature.
	var LC_GMT = "0";
	// Note that this does not take into account daylight savings.
	// You should add 1 to your GMT offset if daylight savings is
	// currently active in your area.

/////////////// END CONFIGURATION /////////////////////////
///////////////////////////////////////////////////////////

// Globals:
	var LC_HTML; var LC_AMPM;

// The following arrays contain data which is used in the
// clock's date function.
	var LC_DaysOfWeek = new Array(7);
		LC_DaysOfWeek[0] = (LC_Abbrev) ? "Sun" : "Sunday";
		LC_DaysOfWeek[1] = (LC_Abbrev) ? "Mon" : "Monday";
		LC_DaysOfWeek[2] = (LC_Abbrev) ? "Tue" : "Tuesday";
		LC_DaysOfWeek[3] = (LC_Abbrev) ? "Wed" : "Wednesday";
		LC_DaysOfWeek[4] = (LC_Abbrev) ? "Thu" : "Thursday";
		LC_DaysOfWeek[5] = (LC_Abbrev) ? "Fri" : "Friday";
		LC_DaysOfWeek[6] = (LC_Abbrev) ? "Sat" : "Saturday";

	var LC_MonthsOfYear = new Array(12);
		LC_MonthsOfYear[0] = (LC_Abbrev) ? "Jan" : "January";
		LC_MonthsOfYear[1] = (LC_Abbrev) ? "Feb" : "February";
		LC_MonthsOfYear[2] = (LC_Abbrev) ? "Mar" : "March";
		LC_MonthsOfYear[3] = (LC_Abbrev) ? "Apr" : "April";
		LC_MonthsOfYear[4] = (LC_Abbrev) ? "May" : "May";
		LC_MonthsOfYear[5] = (LC_Abbrev) ? "Jun" : "June";
		LC_MonthsOfYear[6] = (LC_Abbrev) ? "Jul" : "July";
		LC_MonthsOfYear[7] = (LC_Abbrev) ? "Aug" : "August";
		LC_MonthsOfYear[8] = (LC_Abbrev) ? "Sep" : "September";
		LC_MonthsOfYear[9] = (LC_Abbrev) ? "Oct" : "October";
		LC_MonthsOfYear[10] = (LC_Abbrev) ? "Nov" : "November";
		LC_MonthsOfYear[11] = (LC_Abbrev) ? "Dec" : "December";

// This array controls how often the clock is updated,
// based on your selection in the configuration.
	var LC_ClockUpdate = new Array(3);
		LC_ClockUpdate[0] = 0;
		LC_ClockUpdate[1] = 1000;
		LC_ClockUpdate[2] = 60000;

// Basic browser detection:
	var LC_IE = (document.all) ? 1 : 0;
	var LC_NS = (document.layers) ? 1 : 0;
	var LC_N6 = (window.sidebar) ? 1 : 0;
	var LC_Old = (!LC_IE && !LC_NS && !LC_N6) ? 1 : 0;

// For Version 4+ browsers, write the appropriate HTML to the
// page for the clock, otherwise, attempt to write a static
// date to the page.
	var LC_StartTags = (LC_NS) ? '<table cellpadding="0" cellspacing="0" border="0" width="'+LC_Width+'"><tr><td>' : '';
	if (LC_IE || LC_N6) { LC_ClockTags = '<div id="LiveClockIE" style="width:'+LC_Width+'px; background-color:'+LC_Back_Color+'"></div>'; }
	else if (LC_NS) { LC_ClockTags = '<ilayer width="'+LC_Width+'" bgColor="'+LC_Back_Color+'" id="ClockPosNS"><layer id="LiveClockNS"></layer></ilayer>'; }
	var LC_EndTags = (LC_NS) ? '</td></tr></table>' : '';

	if (!LC_Old) { document.write(LC_StartTags+LC_ClockTags+LC_EndTags); }
	else { show_clock(); }

	onload = init;
	function init() {
		if (!LC_Old) { show_clock(); }
// If you have any other scripts which use the "onload" event,
// call them here:

	}

// The main part of the script:
	function show_clock() {

	// Get all our date variables:
		var time = new Date();
	if (LC_GMT) {
		var offset = time.getTimezoneOffset();
			if (parseInt(navigator.appVersion) == 4 && LC_NS) { offset += 60; }
			if (navigator.appVersion.indexOf('MSIE 3') != -1) { offset = offset * (-1); }
			time.setTime(time.getTime() + offset*60000);
			time.setTime(time.getTime() + LC_GMT*3600000);
	}
		var day = time.getDay();
		var mday = time.getDate();
		var month = time.getMonth();
		var hours = time.getHours();
		var minutes = time.getMinutes();
		var seconds = time.getSeconds();
		var year = time.getYear();

	// Fix the "year" variable for Y2K:
		if (year < 1900) { year += 1900; }

	// Add appropriate "th" if displaying full date:
		if (LC_DisplayDate >= 3) {
			mday += "";
			abbrev = "th";
			if (mday.charAt(mday.length-2) != 1) {
				if (mday.charAt(mday.length-1) == 1) { abbrev = "st"; }
				else if (mday.charAt(mday.length-1) == 2) { abbrev = "nd"; }
				else if (mday.charAt(mday.length-1) == 3) { abbrev = "rd"; }
			}
			mday += abbrev;
		}

	// Set up the hours for either 24 or 12 hour display:
		if (LC_12_Hour) {
			LC_AMPM = "AM";
			if (hours >= 12) { LC_AMPM = "PM"; hours -= 12; }
			if (hours == 0) { hours = 12; }
		}
		if (minutes <= 9) { minutes = "0"+minutes; }
		if (seconds <= 9) { seconds = "0"+seconds; }

	// This is the actual HTML of the clock. If you're going to play around
	// with this, be careful to keep all your quotations in tact.
		LC_HTML = '<font style="color:'+LC_Font_Color+'; font-family:'+LC_Font_Face+'; font-size:'+LC_Font_Size+'pt;">';
		LC_HTML += LC_OpenTags;
		LC_HTML += hours+':'+minutes;
		if (LC_Update == 1) { LC_HTML += ':'+seconds; }
		if (LC_12_Hour) { LC_HTML += ' '+LC_AMPM; }
		if (LC_DisplayDate == 1) { LC_HTML += ' '+mday+'/'+(month+1)+'/'+year; }
		if (LC_DisplayDate == 2) { LC_HTML += ' '+(month+1)+'/'+mday+'/'+year; }
		if (LC_DisplayDate >= 3) { LC_HTML += ' on '+LC_DaysOfWeek[day]+', '+mday+' '+LC_MonthsOfYear[month]; }
		if (LC_DisplayDate >= 4) { LC_HTML += ' '+year; }
		LC_HTML += LC_CloseTags;
		LC_HTML += '</font>';
		
		if (LC_Old) {
			document.write(LC_HTML);
			return;
		}

	// Write the clock to the layer:
		if (LC_NS) {
			clockpos = document.layers["ClockPosNS"];
			liveclock = clockpos.document.layers["LiveClockNS"];
			liveclock.document.write(LC_HTML);
			liveclock.document.close();
		} else if (LC_IE) {
			LiveClockIE.innerHTML = LC_HTML;
		} else if (LC_N6) {
			document.getElementById("LiveClockIE").innerHTML = LC_HTML;
		}

	if (LC_Update != 0) { setTimeout("show_clock()",LC_ClockUpdate[LC_Update]); }
}
