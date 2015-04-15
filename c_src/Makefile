CXX=g++
CXXFLAGS=-Wall -O3 -std=gnu++0x

SRCDIR=src
BINDIR=bin
OBJDIR=obj
INCDIR=include


all: Akaticker

dirs:
	mkdir -p bin
	mkdir -p obj

Akaticker: dirs $(BINDIR)/Akaticker

$(OBJDIR)/%.o: $(SRCDIR)/%.cc
	$(CXX) -I $(INCDIR) $(CXXFLAGS) -c -o $@ $<

$(BINDIR)/Akaticker: $(OBJDIR)/InotifyController.o $(RGBLIB)
	$(CXX) -I $(RGB_INCDIR) $(CXXFLAGS) $^ -o $@  $(LDFLAGS) 






#RGB_DIR=rpi-rgb-led-matrix
#RGB_INCDIR=$(RGB_DIR)/include
#RGB_LIBDIR=$(RGB_DIR)/lib
#RGB_LIBRARY_NAME=rgbmatrix
#RGB_LIBRARY=$(RGB_LIBDIR)/lib$(RGB_LIBRARY_NAME).a
#LDFLAGS+=-L$(RGB_LIBDIR) -l$(RGB_LIBRARY_NAME) -lrt -lm -lpthread

#all: scan_dir
#
#$(RGB_LIBRARY):
#	$(MAKE) -C $(RGB_LIBDIR)
#
#Akaticker : $(OBJECTS) $(RGB_LIBRARY)
#	$(CXX) $(CXXFLAGS) $(OBJECTS) -o $@ $(LDFLAGS)
#
#%.o : %.cc
#	$(CXX) -I$(RGB_INCDIR) $(CXXFLAGS) -c -o $@ $<
#
#scan_dir: scan_dir.o $(RGB_LIBRARY) InotifyController.o
#	$(CXX) $(CXXFLAGS) $^ -o $@ $(LDFLAGS)
#
#clean:
#	rm -f $(OBJECTS) $(BINARIES)
#	$(MAKE) -C $(RGB_LIBDIR) clean
