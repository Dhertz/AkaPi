#include <iostream>
#include <cstring>
#include <list>
#include <led-matrix.h>
#include <condition_variable>
#include <thread>
#include <deque>
#include <memory>
#include <InotifyController.hpp>
#include <utility>
#include <unordered_map>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <dirent.h>
#include <exception>
#include <cstdlib>
#include <Image.h>
#define SCREENS 8
using namespace rgb_matrix;

int speed = 0;
const int sleep_len = 1;

std::mutex m;
std::mutex imghash_mutex;
std::string rel_path;
typedef std::map<std::string,LinkedScrollingImage*> hash_t;
hash_t imhash;
typedef hash_t::iterator iter_type;


bool is_onscreen(iter_type it, int screen_width) {
	return it->second->offset > -(it->second->width) && it->second->offset < screen_width;
}

void draw_screen(Canvas* canvas, int offset, hash_t &images) {
	Pixel p;
	int width = canvas->width();
	int height =  canvas ->height();
	int count = 0;
	for (int y = 0; y < height; y++) {
		for (int x = 0; x < width; x++) {
			count = 0;
			for (auto it = images.begin(); it != images.end(); it++) {
				count++;
				int offset = it->second->offset;//get_offset(it,images);
				if (is_onscreen(it,width) && (x - offset < it->second->width && x - offset >= 0 && y < it->second->height)) {
					p = it->second->image[x-offset + it->second->width*y];
					canvas->SetPixel(x,y,p.red,p.green,p.blue);
					break;
				} else {
					if (x-offset == it->second->width) {
						memset(&p,0,sizeof(p));
						canvas->SetPixel(x,y,p.red,p.green,p.blue);
						break;
					}
				}
			}
		}
	}
	return;
}

int find_max_offset(hash_t& images) {
	int offset = 0;
	for (auto &im : images) {
		if ( offset < (im.second->offset + im.second->width)) {
			offset = im.second->offset + im.second->width;
		}	
	}
	return offset;
}

/* Offset ranges between 0 and .... */
void update_offset(hash_t &images, int width) {
	int acc = 10;
	for (auto it = images.begin(); it != images.end(); it++) {
		it->second->offset = --(it->second->offset);
		if (it->second->offset < -(it->second->width)) {
			int maxoffset = find_max_offset(images);
			if (maxoffset < width) {
				maxoffset = width;
			}
			it->second->offset = maxoffset;
		}
	}
}

int calculate_offset() {
	int offset = 0;
	for (auto &im : imhash) {
		if (im.second->offset > offset) {
			offset = im.second->offset + im.second->width + 5;
		}
	}
	return offset;
}	

void update_display() {
	//process data
	GPIO io;
    	if (!io.Init()) return ;
   	Canvas *canvas = new RGBMatrix(&io, 16, SCREENS, 1);
	std::unique_lock<std::mutex> lk(imghash_mutex);
	while(true) {
		if (!lk.owns_lock()) {
			lk.lock();
		}
		update_offset(imhash,canvas->width());
		usleep(speed);
		draw_screen(canvas,0,imhash);
		//TODO: fix locking..
		lk.unlock();
	}

}


void fixImages(struct inotify_event* e) {
	std::string file_name(e->name);
	std::string ppm(".ppm");
	if (!(file_name.find(ppm) == std::string::npos)) {
			file_name = rel_path + file_name;
			LinkedScrollingImage* loaded_ppm;
			if (e->mask & (IN_CREATE | IN_CLOSE_WRITE) ){
				if (imhash.find(file_name) == imhash.end()) { 
					std::cout << "Adding " << file_name << " to image hash\n";
					loaded_ppm =  LoadPPM((file_name).c_str());
					if (loaded_ppm == NULL) { throw std::bad_alloc(); }
					std::lock_guard<std::mutex> imghash_lock(imghash_mutex);
					loaded_ppm->offset = calculate_offset();
					imhash[file_name] = loaded_ppm;
				} else {
					std::cout << "Updating " << file_name << " in image hash\n";
					loaded_ppm =  LoadPPM((file_name).c_str());
					if (loaded_ppm == NULL) { throw std::bad_alloc();}
					std::lock_guard<std::mutex> imghash_lock(imghash_mutex);
					loaded_ppm->offset = imhash[file_name]->offset;
					free(imhash[file_name]);
					imhash[file_name] = loaded_ppm;
				}
			}
			if (e->mask & IN_DELETE) {
				if (imhash.find(file_name) != imhash.end()) {
					std::cout << "Removing " << file_name << " from image hash\n";
					std::lock_guard<std::mutex> imghash_lock(imghash_mutex);
					free(imhash[file_name]);
					imhash.erase(file_name);
				}
			}
	}
	return;
}
int main(int argc, char** argv) {
	if (argc < 3) { std::cout << "usage: " << argv[0] << " directory speed(ms)\n"; return 1;}
	rel_path = argv[1];
	speed = atoi(argv[2]);
	std::thread t1(update_display);
	try {
		InotifyController inctl;
		inctl.WatchPath(rel_path,IN_CREATE|IN_CLOSE_WRITE);
		inctl.RegisterCallback(rel_path,fixImages);
		inctl.WatchLoop();
	} catch (std::exception& e) {
		std::cerr << "EXCEPTION: " << e.what() << std::endl;
		exit(1);
	}
	t1.join();
	return 0;
}
