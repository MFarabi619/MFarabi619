# { a.b.c = 1; }
# let
#   x = 1;
#   y = 2;
# in
# x + y

# let
#   x = 1;
#   y = 2;
# in
# x + y

# {
#   string = "hello";
#   integer = 1;
#   float = 3.141;
#   bool = true;
#   null = null;
#   list = [
#     1
#     "two"
#     false
#   ];
#   attribute-set = {
#     a = "hello";
#     b = 2;
#     c = 2.718;
#     d = false;
#   }; # comments are supported
# }

# rec {
#   one = 1;
#   two = one + 1;
#   three = two + 1;
# }

# {
#   one = 1;
#   two = one + 1;
#   three = two + 1;
# }

# let
#   a = 1;
# in
# a + a

# let
#   b = a + 1;
#   a = 1;
# in
# a + b

# let
#   attrset = {
#     x = 1;
#   };
# in
# attrset.x

# let
#   attrset = {
#     a = {
#       b = {
#         c = 1;
#       };
#     };
#   };
# in
# attrset.a.b.c

# { a.b.c = 1; }

# let
#   a = {
#     x = 1;
#     y = 2;
#     z = 3;
#   };
# in
# with a;
# [
#   x
#   y
#   z
# ]

# let
#   x = 1;
#   y = 2;
# in
# {
#   inherit x y;
# }

# let
#   a = {
#     x = 1;
#     y = 2;
#   };
# in
# {
#   inherit (a) x y;
# }

# let
#   inherit
#     ({
#       x = 1;
#       y = 2;
#     })
#     x
#     y
#     ;
# in
# [
#   x
#   y
# ]

# let
#   name = "Nix";
# in
# "hello ${name}"

# let
#   a = "no";
# in
# "${a + " ${a}"}"
