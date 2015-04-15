#include <sys/inotify.h>
#include <map>
#include <string>
#include <functional>
#define MAX_EVENTS 1024 /*Max. number of events to process at one go*/
#define LEN_NAME 16 /*Assuming that the length of the filename won't exceed 16 bytes*/
#define EVENT_SIZE  ( sizeof (struct inotify_event) ) /*size of one event*/
#define BUF_LEN     ( MAX_EVENTS * ( EVENT_SIZE + LEN_NAME )) /*buffer to store the data of events*/
typedef std::function<void(struct inotify_event*)> CallbackFunc;
//typedef void(std::string&) callback_t;
class InotifyController {
	public:
		InotifyController();
		InotifyController(std::string &path);
		~InotifyController();
		void WatchPath(std::string &path, int flags);
		void RegisterCallback(std::string &path, CallbackFunc f);
		void WatchLoop(void);
		//		void WatchPath(std::string &path, int flags, std::function<> f);
		struct inotify_event* getEvent();
	private:
		int fd;
		char buffer[BUF_LEN];
		std::map<int,std::string> file_map;
		std::map<std::string,CallbackFunc> func_map;
};
