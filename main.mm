#include <objc/runtime.h>
#import <signal.h>
#import <sys/sysctl.h>
#import <arpa/inet.h>
#import <spawn.h>

typedef long BKSOpenApplicationErrorCode;
enum {
	BKSOpenApplicationErrorCodeNone = 0,
};

extern NSString *BKSActivateForEventOptionTypeBackgroundContentFetching;
extern NSString *BKSDebugOptionKeyArguments;
extern NSString *BKSDebugOptionKeyEnvironment;
extern NSString *BKSDebugOptionKeyStandardOutPath;
extern NSString *BKSDebugOptionKeyStandardErrorPath;
extern NSString *BKSDebugOptionKeyWaitForDebugger;
extern NSString *BKSDebugOptionKeyDisableASLR;
extern NSString *BKSOpenApplicationOptionKeyDebuggingOptions;
extern NSString *BKSOpenApplicationOptionKeyUnlockDevice;
extern NSString *BKSOpenApplicationOptionKeyActivateForEvent;
extern NSString *BKSDebugOptionKeyDebugOnNextLaunch;
extern NSString *BKSDebugOptionKeyCancelDebugOnNextLaunch;

@interface BKSSystemService : NSObject {
	// FBSSystemService* _fbsSystemService;
}
-(void)cleanupClientPort:(unsigned)arg1 ;
-(void)openApplication:(id)arg1 options:(id)arg2 clientPort:(unsigned)arg3 withResult:(/*^block*/id)arg4 ;
-(void)terminateApplication:(id)arg1 forReason:(int)arg2 andReport:(BOOL)arg3 withDescription:(id)arg4 ;
-(void)terminateApplicationGroup:(int)arg1 forReason:(int)arg2 andReport:(BOOL)arg3 withDescription:(id)arg4 ;
-(id)init;
-(void)dealloc;
-(void)openApplication:(id)arg1 options:(id)arg2 withResult:(/*^block*/id)arg3 ;
-(id)systemApplicationBundleIdentifier;
-(int)pidForApplication:(id)arg1 ;
-(unsigned)createClientPort;
-(void)openURL:(id)arg1 application:(id)arg2 options:(id)arg3 clientPort:(unsigned)arg4 withResult:(/*^block*/id)arg5 ;
-(BOOL)canOpenApplication:(id)arg1 reason:(int*)arg2 ;
@end

@interface LSResourceProxy : NSObject // _LSQueryResult -> NSObject
@property (nonatomic,readonly) NSString *primaryIconName;
@end

@interface LSBundleProxy : LSResourceProxy
@property (nonatomic,readonly) NSString *localizedShortName;
@property (nonatomic,readonly) NSString *bundleExecutable;
@property (nonatomic,readonly) NSString *bundleIdentifier;
-(id)localizedName;
@end

@interface LSApplicationProxy : LSBundleProxy
@property (nonatomic,readonly) NSString *itemName;
@property (nonatomic,readonly) NSString *applicationType; // User, System
@property (nonatomic,readonly) NSUInteger installType;
@end

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (id)allApplications;
@end

@interface SUKeybagInterface : NSObject
+ (id)sharedInstance;
@property (nonatomic,readonly) BOOL isPasscodeLocked;
@end

static inline BOOL isLocalPortOpen(short port)
{
	struct sockaddr_in addr;
	int sock = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);

	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_port = htons(port);

	if (inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)) {
		int result = connect(sock, (struct sockaddr *)&addr, sizeof(addr));
		if (result == 0) {
			close(sock);
			return YES;
		}
	}

	return NO;
}

// https://stackoverflow.com/questions/6610705/how-to-get-process-id-in-iphone-or-ipad
static inline int getPID(NSString *processNameSearch)
{
	int pid = -1;
	int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL ,0};

	size_t miblen = 4;
	size_t size;
	int st = sysctl(mib, miblen, NULL, &size, NULL, 0);
	struct kinfo_proc * process = NULL;
	struct kinfo_proc * newprocess = NULL;

	do {
		size += size / 10;
		newprocess = (kinfo_proc *)realloc(process, size);

		if (!newprocess) {
			if (process) {
				free(process);
				process = NULL;
			}

			return pid;
		}

		process = newprocess;
		st = sysctl(mib, miblen, process, &size, NULL, 0);
	} while (st == -1 && errno == ENOMEM);

	if (st == 0) {
		if (size % sizeof(struct kinfo_proc) == 0) {
			int nprocess = size / sizeof(struct kinfo_proc);
			if (nprocess) {
				// char line[10];
				for (int i = nprocess - 1; i >= 0; i--) {
					NSString *processName = [[NSString alloc] initWithFormat:@"%s", process[i].kp_proc.p_comm];

					if ([processName isEqualToString:processNameSearch]) {
						pid = process[i].kp_proc.p_pid;
						[processName release];
						break;
					}

					[processName release];
				}
			}
		}

		free(process);
		process = NULL;
	}

	return pid;
}

static inline BOOL killProcessByName(NSString *executableName, pid_t *pid)
{
	pid_t p;
	int status;
	int lastpid = *pid;
	char *argv[] = {"killall", "-9", (char *)[executableName UTF8String], NULL};
	posix_spawn(&p, "/usr/bin/killall", NULL, NULL, argv, NULL);

	fprintf(stderr, "Waiting for Process to close...\n");
	[NSThread sleepForTimeInterval:2.0f];
	*pid = getPID(executableName);
	if (lastpid == *pid) {
		fprintf(stderr, "ERROR - could not kill Process (%d == %d)\n", lastpid, *pid);
		return NO;
	}

	return YES;
}

static void showHelp()
{
	fprintf(stderr, "Usage:\n");
	fprintf(stderr, "    -b <AppBundleID>    - Bundle Identifier of the Application \n");
	fprintf(stderr, "                            \"com.apple.MobileSMS\"\n");
	fprintf(stderr, "    -n <AppName>        - Application Name, ExecutableName, IconName or LocalizedName\n");
	fprintf(stderr, "                            \"Messages\"\n");
	fprintf(stderr, "    -x <ExecutableName> - Executable Name\n");
	fprintf(stderr, "                            \"backboardd\"\n");
	fprintf(stderr, "    -e                  - Enable Cycript for the given Process\n");
	fprintf(stderr, "                            Then, if it is an App, restart it\n");
	fprintf(stderr, "    -d                  - Disable Cycript for the given Process\n");
	fprintf(stderr, "                            Then, if it is an App, restart it\n");
	fprintf(stderr, "                        If both enable and disable are set,\n");
	fprintf(stderr, "                            Cycript will be loaded and then unloaded when done\n");
	fprintf(stderr, "    -h                  - This help file\n");
	fprintf(stderr, "    You must choose an (AppBundleID or AppName or ExecutableName) and options for (enable and/or disable Cycript)\n");
}

int main(int argc, char **argv, char **envp)
{
	int retVal = 0;
	BOOL enable = NO;
	BOOL disable = NO;
	BOOL force = NO;
	BOOL executable = NO;
	NSString *bundleIdentifier = nil;
	NSString *applicationName = nil;
	NSString *executableName = nil;

	for (int i = 0; i < argc; i++) {
		if (strcmp(argv[i], "--bundle") == 0 || strcmp(argv[i], "-b") == 0) {
			bundleIdentifier = [NSString stringWithUTF8String:argv[++i]];
		} else if (strcmp(argv[i], "--name") == 0 || strcmp(argv[i], "-n") == 0) {
			applicationName = [NSString stringWithUTF8String:argv[++i]];
		} else if (strcmp(argv[i], "--exec") == 0 || strcmp(argv[i], "-x") == 0) {
			executableName = [NSString stringWithUTF8String:argv[++i]];
			executable = YES;
			bundleIdentifier = @"";
			applicationName = executableName;
		} else if (strcmp(argv[i], "--enable") == 0 || strcmp(argv[i], "-e") == 0) {
			enable = YES;
		} else if (strcmp(argv[i], "--disable") == 0 || strcmp(argv[i], "-d") == 0) {
			disable = YES;
		} else if (strcmp(argv[i], "--force") == 0 || strcmp(argv[i], "-f") == 0) {
			force = YES;
		} else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
			showHelp();
			return 1;
		}
	}

	if ((!bundleIdentifier && !applicationName && !executableName) || (!enable && !disable)) {
		showHelp();
		return 1;
	}

	if ([bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
		applicationName = @"SpringBoard";
		executableName = @"SpringBoard";
	} else if (applicationName && [applicationName rangeOfString:@"SpringBoard" options:NSCaseInsensitiveSearch].location != NSNotFound) {
		applicationName = @"SpringBoard";
		executableName = @"SpringBoard";
		bundleIdentifier = @"com.apple.springboard";
	} else {
		LSApplicationWorkspace *applicationWorkspace = [LSApplicationWorkspace defaultWorkspace];
		NSArray *proxies = [applicationWorkspace allApplications];

		for (LSApplicationProxy *proxy in proxies) {
			if (bundleIdentifier && [bundleIdentifier isEqualToString:proxy.bundleIdentifier]) {
				executableName = proxy.bundleExecutable;
				applicationName = proxy.localizedName;
				break;
			} else if (executableName) {
				if ([executableName isEqualToString:proxy.bundleExecutable]) {
					executable = NO;
					bundleIdentifier = proxy.bundleIdentifier;
					applicationName = proxy.localizedName;
					break;
				}
			} else if (applicationName) {
				BOOL found = NO;
				if ([applicationName isEqualToString:proxy.bundleExecutable]) {
					found = YES;
					executableName = proxy.bundleExecutable;
					bundleIdentifier = proxy.bundleIdentifier;
				} else if ([applicationName isEqualToString:proxy.localizedName]) {
					found = YES;
					executableName = proxy.bundleExecutable;
					bundleIdentifier = proxy.bundleIdentifier;
				} else if ([applicationName isEqualToString:proxy.itemName]) {
					found = YES;
					executableName = proxy.bundleExecutable;
					bundleIdentifier = proxy.bundleIdentifier;
				} else if ([applicationName isEqualToString:proxy.primaryIconName]) {
					found = YES;
					executableName = proxy.bundleExecutable;
					bundleIdentifier = proxy.bundleIdentifier;
				}

				// fprintf(stderr, "found %d, %s, %s, %s\n", proxy.installType, [proxy.applicationType UTF8String], [proxy.bundleExecutable UTF8String], [proxy.bundleIdentifier UTF8String]);

				if (found) {
					break;
				}
			}
		}
	}

	if (!bundleIdentifier) {
		fprintf(stderr, "ERROR - could not find bundleIdentifier for %s\n", [applicationName UTF8String]);
		return 1;
	}

	if (!executableName) {
		fprintf(stderr, "ERROR - could not find executableName for %s\n", [bundleIdentifier UTF8String]);
		return 1;
	}

	BOOL isPasscodeLocked = [[objc_getClass("SUKeybagInterface") sharedInstance] isPasscodeLocked];

	NSArray *filterFileObjectList = nil;
	int pid = getPID(executableName);
	BOOL isCycriptRunning = isLocalPortOpen(8556);
	if (isCycriptRunning) {
		NSDictionary *filterFile = [NSDictionary dictionaryWithContentsOfFile:@"/Library/MobileSubstrate/DynamicLibraries/cycriptListener.plist"];
		NSDictionary *filter = [filterFile objectForKey:@"Filter"];
		filterFileObjectList = [filter objectForKey:@"Bundles"] ?: [filter objectForKey:@"Executables"];
		[filterFile release];
	}

	fprintf(stderr, "applicationName: %s is %s (%d)\n    executableName: %s\n    bundleIdentifier: %s\n    Cycript is %s: %s\n    Device is%s passcode locked\n", [applicationName UTF8String], pid == -1 ? "not running" : "running", pid, [executableName UTF8String], [bundleIdentifier UTF8String], isCycriptRunning ? "active" : "inactive", filterFileObjectList ? [[filterFileObjectList objectAtIndex:0] UTF8String] : "", isPasscodeLocked ? "" : " not");

	if (isPasscodeLocked && enable && ![executableName isEqualToString:@"SpringBoard"] && !executable) {
		fprintf(stderr, "WARNING - Since your device is passcode locked and you are trying to enable Cycript for an App, there is a good chance this will fail!\n");
	}

	if (isCycriptRunning && !enable && disable) {
		if (executable) {
			if (filterFileObjectList && ![executableName isEqualToString:[filterFileObjectList objectAtIndex:0]]) {
				fprintf(stderr, "WARNING - Cycript is active but it looks like the executableName you are trying to disable it for does not match!\n");
			}
		} else {
			if (filterFileObjectList && ![bundleIdentifier isEqualToString:[filterFileObjectList objectAtIndex:0]]) {
				fprintf(stderr, "WARNING - Cycript is active but it looks like the bundleIdentifier you are trying to disable it for does not match!\n");
			}
		}
	}

	if (executable && pid == -1 && enable) {
		fprintf(stderr, "WARNING - You are trying to enable Cycript for an executable that is not running. Cyrun cannot confirm whether or not this is valid!\n");
	}

	if (!force) {
		fprintf(stderr, "Do you want to continue %s Cycript (y or n)? ", enable ? "enabling" : "disabling");

		char line[10];
		if (fgets(line, sizeof(line), stdin) == NULL) {
			printf("ERROR - Input.\n");
			return 1;
		}

		if (line[0] != 'y' && line[0] != 'Y') {
			fprintf(stderr, "Ok, cancelled\n");
			return 1;
		}
	}

	if (enable) {
		if (isCycriptRunning) {
			fprintf(stderr, "ERROR - Cannot enable because Cycript is already active\n");
			fprintf(stderr, "You can probably disable it with\n    cyrun -b %s -d\n", [[filterFileObjectList objectAtIndex:0] UTF8String]);
			return 1;
		}

		NSDictionary *filter = nil;
		if (executable) {
			filter = [NSDictionary dictionaryWithObjectsAndKeys:
				@[executableName], @"Executables",
				nil
			];
		} else {
			filter = [NSDictionary dictionaryWithObjectsAndKeys:
				@[bundleIdentifier], @"Bundles",
				nil
			];
		}

		NSDictionary *filterFile = [NSDictionary dictionaryWithObjectsAndKeys:
			filter, @"Filter",
			nil
		];

		[filterFile writeToFile:@"/Library/MobileSubstrate/DynamicLibraries/cycriptListener.plist" atomically:YES];
		[filter release];
		[filterFile release];

		if ([NSFileManager.defaultManager fileExistsAtPath:@"/Library/MobileSubstrate/DynamicLibraries/cycriptListener.disabled"]) {
			NSError *error = NULL;
			BOOL result = YES;
			if ([NSFileManager.defaultManager fileExistsAtPath:@"/Library/MobileSubstrate/DynamicLibraries/cycriptListener.dylib"]) {
				// this might happen right after reinstalling the tweak
				result = [NSFileManager.defaultManager removeItemAtPath:@"/Library/MobileSubstrate/DynamicLibraries/cycriptListener.disabled" error:&error];
			} else {
				result = [NSFileManager.defaultManager moveItemAtPath:@"/Library/MobileSubstrate/DynamicLibraries/cycriptListener.disabled" toPath:@"/Library/MobileSubstrate/DynamicLibraries/cycriptListener.dylib" error:&error];
				if (!result) {
					fprintf(stderr, "ERROR - enabling dylib file\n    (%ld) %s\n", error.code, [error.localizedDescription UTF8String]);
					return 1;
				}
			}
		}

		if (pid != -1) {
			// [systemService terminateApplication:bundleIdentifier forReason:0 andReport:NO withDescription:@"cyrun"];
			BOOL success = killProcessByName(executableName, &pid);
			if (!success) {
				return 1;
			}
		}

		if (!executable && ![bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
			BKSSystemService *systemService = [[BKSSystemService alloc] init];
			NSMutableDictionary *options = [NSMutableDictionary dictionary];

			if (isPasscodeLocked) {
				[options setObject:[NSNumber numberWithBool:NO] forKey:BKSOpenApplicationOptionKeyUnlockDevice];
				[options setObject:[NSNumber numberWithBool:YES] forKey:@"__ActivateSuspended"];
			} else {
				[options setObject:[NSNumber numberWithBool:YES] forKey:BKSOpenApplicationOptionKeyUnlockDevice];
			}

			__block BKSOpenApplicationErrorCode openApplicationErrorCode = BKSOpenApplicationErrorCodeNone;
			__block dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
			[systemService openApplication:bundleIdentifier options:options withResult:^(NSError *error) {
					if (error) {
						fprintf(stderr, "ERROR - openApplication failed for %s\n    (%ld) %s\n", [bundleIdentifier UTF8String], error.code, [error.localizedDescription UTF8String]);
						openApplicationErrorCode = (BKSOpenApplicationErrorCode)[error code];
					}

					dispatch_semaphore_signal(semaphore);
				}
			];

			const uint32_t timeoutDuration = 10;
			dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, timeoutDuration * NSEC_PER_SEC);
			long success = dispatch_semaphore_wait(semaphore, timeout) == 0;

			if (!success) {
				fprintf(stderr, "ERROR - openApplication timeout for %s\n", [bundleIdentifier UTF8String]);
				retVal = 1;
			} else if (openApplicationErrorCode != BKSOpenApplicationErrorCodeNone) {
				retVal = 1;
			} else {
				pid = getPID(executableName);
				if (pid == -1) {
					fprintf(stderr, "ERROR - could not launch App, pid not found for %s\n", [executableName UTF8String]);
					retVal = 1;
				} else {
					isCycriptRunning = isLocalPortOpen(8556);
					fprintf(stderr, "Waiting for Cycript to become active...\n");
					for (int i = 0; i < 5 && !isCycriptRunning; i++) {
						[NSThread sleepForTimeInterval:1.0f];
						isCycriptRunning = isLocalPortOpen(8556);
					}

					if (!isCycriptRunning) {
						fprintf(stderr, "ERROR - could not connect to Cycript\n");
						retVal = 1;
					} else {
						fprintf(stderr, "Successfully enabled, you may now run\n    cycript -r 127.0.0.1:8556\n");
					}
				}
			}

			dispatch_release(semaphore);
			[systemService release];
			[options release];
		} else {
			if (executable) {
				if ([executableName isEqualToString:@"backboardd"]) {
					fprintf(stderr, "Waiting for backboardd to launch...\n");
					pid = 0;
					[NSThread sleepForTimeInterval:2.0f];
				} else {
					fprintf(stderr, "Waiting for Process to launch...\n");
					pid = getPID(executableName);
					for (int i = 0; i < 60 && pid == -1; i++) {
						[NSThread sleepForTimeInterval:1.0f];
						pid = getPID(executableName);
					}
				}
			} else {
				pid = 0;
				fprintf(stderr, "Waiting for SpringBoard to launch...\n");
				[NSThread sleepForTimeInterval:2.0f];
			}

			if (pid == -1) {
				fprintf(stderr, "ERROR - could not launch Process, pid not found for %s\n", [executableName UTF8String]);
				retVal = 1;
			} else {
				isCycriptRunning = isLocalPortOpen(8556);
				fprintf(stderr, "Waiting for Cycript to become active...\n");
				for (int i = 0; i < 5 && !isCycriptRunning; i++) {
					[NSThread sleepForTimeInterval:1.0f];
					isCycriptRunning = isLocalPortOpen(8556);
				}

				if (!isCycriptRunning) {
					fprintf(stderr, "ERROR - could not connect to Cycript\n");
					retVal = 1;
				} else {
					fprintf(stderr, "Success, you may now run\n    cycript -r 127.0.0.1:8556\n");
				}
			}
		}
	} else {
		if ([NSFileManager.defaultManager fileExistsAtPath:@"/Library/MobileSubstrate/DynamicLibraries/cycriptListener.dylib"]) {
			NSError *error = NULL;
			BOOL result = YES;
			if ([NSFileManager.defaultManager fileExistsAtPath:@"/Library/MobileSubstrate/DynamicLibraries/cycriptListener.disabled"]) {
				// this might happen right after reinstalling the tweak
				result = [NSFileManager.defaultManager removeItemAtPath:@"/Library/MobileSubstrate/DynamicLibraries/cycriptListener.disabled" error:&error];
			}

			result = [NSFileManager.defaultManager moveItemAtPath:@"/Library/MobileSubstrate/DynamicLibraries/cycriptListener.dylib" toPath:@"/Library/MobileSubstrate/DynamicLibraries/cycriptListener.disabled" error:&error];
			if (!result) {
				fprintf(stderr, "ERROR - disabling dylib file\n    (%ld) %s\n", error.code, [error.localizedDescription UTF8String]);
				return 1;
			}
		}

		if (isCycriptRunning) {
			if (pid != -1) {
				BOOL success = killProcessByName(executableName, &pid);
				if (!success) {
					return 1;
				}

				isCycriptRunning = isLocalPortOpen(8556);
				fprintf(stderr, "Waiting for Cycript to be inactive...\n");
				for (int i = 0; i < 5 && isCycriptRunning; i++) {
					[NSThread sleepForTimeInterval:1.0f];
					isCycriptRunning = isLocalPortOpen(8556);
				}

				if (isCycriptRunning) {
					fprintf(stderr, "ERROR - Cycript is still running\n    %s was killed\n", [executableName UTF8String]);
					retVal = 1;
				} else {
					fprintf(stderr, "Successfully disabled\n    %s was killed\n", [executableName UTF8String]);
				}
			} else {
				fprintf(stderr, "Successfully disabled\n");
			}
		} else {
			fprintf(stderr, "Successfully disabled\n    Cycript was not active, so %s was not killed\n", [executableName UTF8String]);
		}
	}

	return retVal;
}
