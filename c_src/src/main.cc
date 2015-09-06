#include <algorithm>
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
#include <chrono>
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
	return it->second->offset > -(it->second->frames->width) && it->second->offset < screen_width;
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
				if (is_onscreen(it,width) && (x - offset < it->second->frames->width && x - offset >= 0 && y < it->second->frames->height)) {
					p = it->second->frames->image[x-offset + it->second->frames->width*y];
					canvas->SetPixel(x,y,p.red,p.green,p.blue);
					break;
				} else {
					if (x-offset == it->second->frames->width) {
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
		if ( offset < (im.second->offset + im.second->frames->width)) {
			offset = im.second->offset + im.second->frames->width;
		}
	}
	return offset;
}

/* Offset ranges between 0 and .... */
void update_offset(hash_t &images, int width) {
	int acc = 10;
	for (auto it = images.begin(); it != images.end(); it++) {
		it->second->offset = --(it->second->offset);
		if (it->second->offset < -(it->second->frames->width)) {
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
			offset = im.second->offset + im.second->frames->width + 5;
		}
	}
	return offset;
}

void update_animations(hash_t& images) {
	auto now = std::chrono::high_resolution_clock::now();
	typedef std::chrono::high_resolution_clock::period period_t;
	auto dur = now.time_since_epoch();
	long cur_millis = std::chrono::duration_cast<std::chrono::milliseconds>(dur).count();
	for (auto &im : images) {
		if(im.second->num_frames <= 1) continue;
		if(!im.second->last_redraw || cur_millis - im.second->last_redraw > 100) {
			im.second->frames = im.second->frames->next;
			im.second->last_redraw = cur_millis;
		}
	}
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
		update_animations(imhash);
		draw_screen(canvas,0,imhash);
		//TODO: fix locking..
		lk.unlock();
		usleep(speed);
	}

}


void fixImages(struct inotify_event* e) {
	std::string file_name(e->name);
	std::string ppm(".ppm");
	if (!(file_name.find(ppm) == std::string::npos)) {
			file_name = rel_path + file_name;
			LinkedScrollingImage* loaded_ppm = new LinkedScrollingImage;
			loaded_ppm->num_frames = 0;
			if (e->mask & (IN_CREATE | IN_CLOSE_WRITE) ){
				if (imhash.find(file_name) == imhash.end()) {
					std::cout << "Adding " << file_name << " to image hash\n";
					Frame *f =  LoadPPM((file_name).c_str());
					loaded_ppm->frames = f;
					loaded_ppm->num_frames++;
					if (loaded_ppm == NULL) { throw std::bad_alloc(); }
					std::lock_guard<std::mutex> imghash_lock(imghash_mutex);
					loaded_ppm->offset = calculate_offset();
					imhash[file_name] = loaded_ppm;
				} else {
					std::cout << "Updating " << file_name << " in image hash\n";
					Frame *f =  LoadPPM((file_name).c_str());
					loaded_ppm->frames = f;
					loaded_ppm->num_frames++;
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

void loadAnimations(std::string rel_path) {
	std::string animation_path = rel_path.append("animations/");
	DIR* dir = opendir(animation_path.c_str());
	if (dir) {
		std::cout << "animations available!\n";
		while (true) {
			struct dirent* de = readdir(dir);
			if (!de) break;
			if (de->d_type != DT_DIR || de->d_name[0] == '.') continue; //not a folder
			std::string folder_path(animation_path.c_str());
			folder_path = folder_path + de->d_name;
			DIR* frames = opendir(folder_path.c_str());
			if (!frames) continue;
			std::vector <std::string> frame_paths;
			while (true) {
				struct dirent* frame = readdir(frames);
				if (frame == NULL) break;
				if (frame->d_type != DT_REG || de->d_name[0] == '.') continue; //not a file
				std::string frame_path(folder_path);
				frame_path = frame_path +  "/" + frame->d_name;
				std::string ppm(".ppm");
				if (frame_path.find(ppm) == std::string::npos) continue;
				frame_paths.push_back(frame_path);
			}
			if (frame_paths.size() < 1) continue; //there are no PPMs in here
			std::sort(frame_paths.begin(), frame_paths.end());
			LinkedScrollingImage *l = new LinkedScrollingImage;
			l->num_frames = 0;
			l->offset = 0;
			Frame *prev_frame;
			for (auto &frame_path : frame_paths) {
				Frame *i = LoadPPM(frame_path.c_str());
				std::cout << "   frame: " << frame_path << '\n';
				if (prev_frame) {
					prev_frame->next = i;
				} else {
					l->frames = i;
				}
				l->num_frames++;
				prev_frame = i;
			}
			prev_frame->next = l->frames;
			std::lock_guard<std::mutex> imghash_lock(imghash_mutex);
			l->offset = calculate_offset();
			std::cout << "adding " << de->d_name << " to hash\n";
			imhash[de->d_name] = l;
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
		loadAnimations(rel_path);
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
