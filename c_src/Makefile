CXX=g++
CXXFLAGS=-Wall -O3 -std=gnu++0x

SRCDIR=src
BINDIR=bin
OBJDIR=obj
INCDIR=include

#RGB Library: https://github.com/hzeller/rpi-rgb-led-matrix
RGB_DIR=rpi-rgb-led-matrix
RGB_INCDIR=$(RGB_DIR)/include
RGB_LIBDIR=$(RGB_DIR)/lib
RGB_LIBRARY_NAME=rgbmatrix
RGB_LIBRARY=$(RGB_LIBDIR)/lib$(RGB_LIBRARY_NAME).a
LDFLAGS+=-L$(RGB_LIBDIR) -l$(RGB_LIBRARY_NAME) -lm -lpthread


all: Akaticker

dirs:
	mkdir -p bin
	mkdir -p obj

$(RGB_LIBRARY): 
	$(MAKE) -C $(RGB_DIR)

Akaticker: dirs $(RGB_LIBRARY) $(BINDIR)/Akaticker

$(OBJDIR)/%.o: $(SRCDIR)/%.cc
	$(CXX) -I $(RGB_INCDIR) -I $(INCDIR) $(CXXFLAGS) -c -o $@ $<

$(BINDIR)/Akaticker: $(OBJDIR)/main.o $(OBJDIR)/InotifyController.o 
	$(CXX) -I $(RGB_INCDIR) -I $(INCDIR) $(CXXFLAGS) $^ -o $@  $(LDFLAGS) 


clean:
	-rm bin/*
	-rm obj/*
	$(MAKE) -C $(RGB_DIR) clean

.PHONY: all clean 
