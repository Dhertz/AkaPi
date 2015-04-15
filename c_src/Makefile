CXXFLAGS=-Wall -O3 -std=gnu++0x
OBJECTS="scan_dir.o InotifyController.o"
RGB_DIR=rpi-rgb-led-matrix
RGB_INCDIR=$(RGB_DIR)/include
RGB_LIBDIR=$(RGB_DIR)/lib
RGB_LIBRARY_NAME=rgbmatrix
RGB_LIBRARY=$(RGB_LIBDIR)/lib$(RGB_LIBRARY_NAME).a
LDFLAGS+=-L$(RGB_LIBDIR) -l$(RGB_LIBRARY_NAME) -lrt -lm -lpthread


$(RGB_LIBRARY):
	$(MAKE) -C $(RGB_LIBDIR)

Akaticker : $(OBJECTS) $(RGB_LIBRARY)
	$(CXX) $(CXXFLAGS) $(OBJECTS) -o $@ $(LDFLAGS)

%.o : %.cc
	$(CXX) -I$(RGB_INCDIR) $(CXXFLAGS) -c -o $@ $<

scan_dir: scan_dir.o $(RGB_LIBRARY) InotifyController.o
	$(CXX) $(CXXFLAGS) $^ -o $@ $(LDFLAGS)

clean:
	rm -f $(OBJECTS) $(BINARIES)
	$(MAKE) -C $(RGB_LIBDIR) clean
