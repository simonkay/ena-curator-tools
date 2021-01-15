function zoom(z) {

  var img = document.getElementById( 'EMBLWorld_img' );
  var img_w = img.width;
  var img_h = img.height;
  var full_img_w = img_w * Math.pow(2, ZOOM_LEVEL-1);
  var full_img_h = img_h * Math.pow(2, ZOOM_LEVEL-1);

  var middle_x = (img_w/2)+ORIG_X;
  var middle_y = (img_h/2)+ORIG_Y;

  var new_middle_x = (middle_x/full_img_w) * (img_w*z);
  var new_middle_y = (middle_y/full_img_h) * (img_h*z);

  var x = Math.floor( new_middle_x - (img_w/2) );
  var y = Math.floor( new_middle_y - (img_h/2) );
  
  show( x, y, z );
}

function zoom_and_center(img, e) {
  e = e || window.event; // support IE's global event object

  if ( ZOOM_LEVEL >= 3 ) {
    return false;
  }
  if (e.pageX) {

    x = e.pageX;
    y = e.pageY;

  } else if (e.clientX) {

    x = e.clientX + document.body.scrollLeft;
    y = e.clientY + document.body.scrollTop;

  } else {

    alert( "ERROR: cannot get coordinates!" );
  }

  x -= img.offsetLeft;
  y -= img.offsetTop;

  x += ORIG_X * Math.pow(2, ZOOM_LEVEL-1);
  y += ORIG_Y * Math.pow(2, ZOOM_LEVEL-1);
dia.innerHTML += x +', '+ y + '<Br>';
  var new_zoom = ZOOM_LEVEL + 1;
  show( x, y, new_zoom );
}

function show( x, y, z ) {

  var img = document.getElementById( 'EMBLWorld_img' );
  var img_w = img.width;
  var img_h = img.height;
  // make it so that the orig coordinates stay within boundaries
  x = x + img_w > z*img_w ? (z-1)*img_w : x;
  y = y + img_h > z*img_h ? (z-1)*img_h : y;
  x = x < 0 ? 0 : x;
  y = y < 0 ? 0 : y;
  
  var url_query = 'z='+ z +'&x='+ x +'&y='+ y;
  var loc = ''+window.location;
  loc = loc.substr(0, loc.indexOf('?'));
  window.location = loc +'?'+ url_query;
}

function pan( pan_x, pan_y ) {

  var x = ORIG_X + pan_x;
  var y = ORIG_Y + pan_y;

  show( x, y, ZOOM_LEVEL );
}

function swap(im, action) {

  im.src='imgs/'+ im.id +'_'+ action + '.png';
}

