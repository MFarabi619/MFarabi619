  for (y=[0:2:20]) {
      translate([0,0,y+1])
          cube([30-2*y,30-2*y,2], true);
  }
