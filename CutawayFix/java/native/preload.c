/*
 * ProjectZomboid64.exe hosts the JVM in-process, so when -javaagent loads
 * instrument.dll during VM startup its imports (java.dll, jli.dll) are resolved
 * through the normal Windows search order (exe dir, system dirs, PATH) instead
 * of jre64\bin. That fails, or picks up another Java installation's DLLs.
 * Listed before -javaagent, this agent loads the game JRE's copies by full path
 * so the later imports bind to the modules already in memory.
 */
#include <windows.h>

static int preload(const wchar_t *binDir, const wchar_t *name)
{
    wchar_t path[MAX_PATH * 2];
    if (lstrlenW(binDir) + lstrlenW(name) + 2 >= (int)(sizeof(path) / sizeof(path[0])))
        return 0;
    lstrcpyW(path, binDir);
    lstrcatW(path, L"\\");
    lstrcatW(path, name);
    return LoadLibraryExW(path, NULL, LOAD_WITH_ALTERED_SEARCH_PATH) != NULL;
}

__declspec(dllexport) int Agent_OnLoad(void *vm, char *options, void *reserved)
{
    (void)vm; (void)options; (void)reserved;

    HMODULE jvm = GetModuleHandleW(L"jvm.dll");
    if (jvm == NULL)
        return 0;

    wchar_t binDir[MAX_PATH * 2];
    DWORD len = GetModuleFileNameW(jvm, binDir, (DWORD)(sizeof(binDir) / sizeof(binDir[0])));
    if (len == 0 || len >= sizeof(binDir) / sizeof(binDir[0]))
        return 0;

    /* <jre>\bin\server\jvm.dll -> <jre>\bin */
    for (int i = 0; i < 2; i++) {
        wchar_t *slash = NULL;
        for (wchar_t *p = binDir; *p; p++)
            if (*p == L'\\' || *p == L'/')
                slash = p;
        if (slash == NULL)
            return 0;
        *slash = 0;
    }

    preload(binDir, L"java.dll");
    preload(binDir, L"jli.dll");
    return 0;
}
