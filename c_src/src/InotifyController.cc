#include <InotifyController.hpp>
#include <iostream>
#include <stdexcept>
#include <sys/inotify.h>
#include <string>

InotifyController::InotifyController() {
	this->fd = inotify_init();
	if (this->fd < 0) {
		throw std::runtime_error("Failed calling inotify_init()");
	}
}

void InotifyController::WatchPath(std::string &path, int flags) {
	int wd = inotify_add_watch(this->fd,path.c_str(),flags);
	if ( wd < 0) {
		throw std::runtime_error("Couldn't call inotify_add_watch on " + path);
	} else {
		std::cerr << "Watching " << path << std::endl;
		file_map[wd]=path;
	}
}

struct inotify_event* InotifyController::getEvent() {
		int length = read(fd,&buffer,BUF_LEN);
		if (length < 0)
			throw std::runtime_error("Error calling read");
		return (struct inotify_event* )&buffer[0];
}

InotifyController::~InotifyController() {
//	inotify_rm_watch(fd,wd);
	close(fd);
}

void InotifyController::RegisterCallback(std::string &path, std::function<void(struct inotify_event*)> f) {
	func_map[path]=f;
}

void InotifyController::WatchLoop(void) {
	while (true) {
		struct inotify_event* event = this->getEvent();
		usleep(100);
       	 	if ( event->mask & IN_MODIFY | IN_CREATE) {
			std::string path = file_map[event->wd];
			if (path.size() == 0) {
				std::cerr << "No function registered for " << event->name << std::endl;
			} else {
				this->func_map[path](event);
        		}
		}
	}
}
