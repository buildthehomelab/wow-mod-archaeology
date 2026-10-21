/*
 * mod-archaeology loader.
 *
 * AzerothCore looks up a loader symbol derived from the module's folder name: for folder
 * "mod-archaeology" that symbol is exactly "Addmod_archaeologyScripts". If you clone the repo
 * under a different folder name, rename this function to match.
 *
 * Released under the MIT License.
 */

void AddArchaeologyAddonScripts();
void AddArchaeologyDigScripts();
void AddArchaeologyDigOrdersScripts();
void AddArchaeologyTraitScripts();
void AddArchaeologyRewardScripts();

void Addmod_archaeologyScripts()
{
    AddArchaeologyAddonScripts();
    AddArchaeologyDigScripts();
    AddArchaeologyDigOrdersScripts();
    AddArchaeologyTraitScripts();
    AddArchaeologyRewardScripts();
}
