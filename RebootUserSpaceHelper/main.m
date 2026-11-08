#include <unistd.h>
#include <xpc/xpc.h>
#include <dlfcn.h>
#include <sys/utsname.h>

int main() {
    
    // 1. 获取系统版本
    struct utsname uts;
    uname(&uts);
    
    // 2. Unlink MemoryMaintenance 的 state 文件 必要步骤,否则不会重启
    // iOS 15及以上系统的mmaintenanced和iOS 15以下的位置不同，所以必须区分
    if (atoi(uts.release) >= 21) {
        unlink("/private/var/mobile/Library/MemoryMaintenance/mmaintenanced");
    } else {
        unlink("/private/var/db/mmaintenanced");
    }
    

    // 3. 因为直接XPC编译器不让,所以动态加载 libxpc
    void *lib = dlopen("/usr/lib/system/libxpc.dylib", RTLD_LAZY);
    if (!lib) {
        return -1;
    }

    // 4. 动态获取函数指针
    xpc_connection_t (*p_xpc_connection_create_mach_service)(const char *, dispatch_queue_t, uint64_t) =
        dlsym(lib, "xpc_connection_create_mach_service");
    xpc_object_t (*p_xpc_dictionary_create)(const char *const *, const xpc_object_t *, size_t) =
        dlsym(lib, "xpc_dictionary_create");
    void (*p_xpc_dictionary_set_uint64)(xpc_object_t, const char *, uint64_t) =
        dlsym(lib, "xpc_dictionary_set_uint64");
    void (*p_xpc_connection_set_event_handler)(xpc_connection_t, xpc_handler_t) =
        dlsym(lib, "xpc_connection_set_event_handler");
    void (*p_xpc_connection_resume)(xpc_connection_t) =
        dlsym(lib, "xpc_connection_resume");
    xpc_object_t (*p_xpc_connection_send_message_with_reply_sync)(xpc_connection_t, xpc_object_t) =
        dlsym(lib, "xpc_connection_send_message_with_reply_sync");
    const char *(*p_xpc_copy_description)(xpc_object_t) =
        dlsym(lib, "xpc_copy_description");

    if (!p_xpc_connection_create_mach_service ||
        !p_xpc_dictionary_create ||
        !p_xpc_dictionary_set_uint64 ||
        !p_xpc_connection_set_event_handler ||
        !p_xpc_connection_resume ||
        !p_xpc_connection_send_message_with_reply_sync ||
        !p_xpc_copy_description) {
        
        dlclose(lib);
        return -1;
    }

    // 5.建立连接
    xpc_connection_t conn = p_xpc_connection_create_mach_service("com.apple.mmaintenanced", NULL, 0);
    if (!conn) {
        dlclose(lib);
        return -1;
    }

    // 简单 event handler，防止崩但记录事件
    p_xpc_connection_set_event_handler(conn, ^(xpc_object_t event){});
    p_xpc_connection_resume(conn);

    // 6. 构造消息 { cmd = 5 }
    xpc_object_t msg = p_xpc_dictionary_create(NULL, NULL, 0);
    p_xpc_dictionary_set_uint64(msg, "cmd", 5);

    // 7. 发送消息并等待同步回复
    p_xpc_connection_send_message_with_reply_sync(conn, msg);

    dlclose(lib);
    return 0;
}
