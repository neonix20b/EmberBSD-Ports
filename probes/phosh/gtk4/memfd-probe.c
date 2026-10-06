/* Diagnose the native memfd mapping constraint independently of GTK. */
#include <sys/mman.h>
#include <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int
main(void)
{
	long page = sysconf(_SC_PAGESIZE);
	int failures = 0;

	if (page <= 1) {
		fprintf(stderr, "Invalid page size: %ld\n", page);
		return 2;
	}
	size_t sizes[] = {1, (size_t)page - 1, (size_t)page,
	    (size_t)page + 1, 801360, 802816};
	printf("page=%ld\n", page);
	for (int sealed = 0; sealed < 2; sealed++) {
		for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
			int fd = memfd_create("gtk4-memfd-probe",
			    MFD_CLOEXEC | MFD_ALLOW_SEALING);
			if (fd < 0) {
				perror("memfd_create");
				return 2;
			}
			if (sealed && fcntl(fd, F_ADD_SEALS, F_SEAL_SHRINK) < 0) {
				perror("fcntl");
				close(fd);
				return 2;
			}
			if (ftruncate(fd, (off_t)sizes[i]) < 0) {
				perror("ftruncate");
				close(fd);
				return 2;
			}
			void *p = mmap(NULL, sizes[i], PROT_READ | PROT_WRITE,
			    MAP_SHARED, fd, 0);
			int error = p == MAP_FAILED ? errno : 0;
			printf("sealed=%d size=%zu map=%s errno=%d (%s)\n",
			    sealed, sizes[i], error ? "FAIL" : "OK", error,
			    error ? strerror(error) : "none");
			if (p == MAP_FAILED)
				failures++;
			else
				munmap(p, sizes[i]);
			close(fd);
		}
	}
	return failures ? 1 : 0;
}
