# The rewarded-ads bridge, built by love-android's lua-modules mechanism
# (app/src/main/cpp/CMakeLists.txt adds every folder under lua-modules/) into
# libliads.so, which src/ads.lua loads with ffi.load("liads"). Links nothing of
# LÖVE's or LuaJIT's: SDL is reached at run time by dlsym (see liads.cpp).

add_library(liads SHARED liads.cpp)
target_link_libraries(liads PRIVATE dl)
