#include <iostream>


struct Pixel {
    uint8_t red;
    uint8_t green;
    uint8_t blue;
};

struct LinkedScrollingImage {
    LinkedScrollingImage *next;
    Pixel *image;
    int32_t offset;
    int32_t width;
    int32_t height;
};
// TODO: Redo loadPPM and Readline to be more sane...
char *ReadLine(FILE *f, char *buffer, size_t len) {
    char *result;
    do {
      result = fgets(buffer, len, f);
    } while (result != NULL && result[0] == '#');
    return result;
}


LinkedScrollingImage* LoadPPM(const char *filename) {
    FILE *f = fopen(filename, "r");
    if (f == NULL) { perror("fopen()"); return NULL; }
    if (flock(fileno(f), LOCK_SH)) {perror("flock()"); fclose(f); return NULL;}

    char header_buf[256];
    const char *line = ReadLine(f, header_buf, sizeof(header_buf));
#define EXIT_WITH_MSG(m) { fprintf(stderr, "%s: %s |%s", filename, m, line); \
      flock(fileno(f), LOCK_UN); fclose(f); return false; }
    if (sscanf(line, "P6 ") == EOF)
      EXIT_WITH_MSG("Can only handle P6 as PPM type.");
    line = ReadLine(f, header_buf, sizeof(header_buf));
    int new_width, new_height;
    if (!line || sscanf(line, "%d %d ", &new_width, &new_height) != 2)
      EXIT_WITH_MSG("Width/height expected");
    int value;
    line = ReadLine(f, header_buf, sizeof(header_buf));
    if (!line || sscanf(line, "%d ", &value) != 1 || value != 255)
      EXIT_WITH_MSG("Only 255 for maxval allowed.");
    const size_t pixel_count = new_width * new_height;
    Pixel *new_image = new Pixel [ pixel_count ];
//    assert(sizeof(Pixel) == 3);   // we make that assumption.
    if (fread(new_image, sizeof(Pixel), pixel_count, f) != pixel_count) {
      line = "";
      EXIT_WITH_MSG("Not enough pixels read.");
    }
#undef EXIT_WITH_MSG
    fclose(f);
    flock(fileno(f), LOCK_UN);
    LinkedScrollingImage *ret = new LinkedScrollingImage;
    ret->image = new_image;
    ret->width = new_width;
    ret->height = new_height;
    ret->offset = 0;
    return ret;
}
