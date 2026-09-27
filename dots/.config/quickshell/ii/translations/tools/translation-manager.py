#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Translation File Management Script
Used to update and extract translatable texts, manage JSON translation file key comparison
"""

import os
import ast
import json
import re
import sys
import argparse
from pathlib import Path
from typing import Dict, Set, List, Tuple
import tempfile
import subprocess

class TranslationManager:
    def __init__(self, translations_dir: str, source_dir: str, yes_mode: bool = False):
        self.translations_dir = Path(translations_dir)
        self.source_dir = Path(source_dir)
        self.temp_extracted_file = None
        self.yes_mode = yes_mode
        
        # Ensure translation directory exists
        self.translations_dir.mkdir(parents=True, exist_ok=True)
        
    def extract_translatable_texts(self) -> Set[str]:
        """Extract translatable texts from source code"""
        translatable_texts = set()
        
        # Search patterns: Translation.tr("text") or Translation.tr('text')
        # Improved regex that handles nested quotes correctly
        patterns = [
            r'Translation\.tr\s*\(\s*(["\'])(((?!\1)[^\\]|\\.)*)(\1)\s*\)',  # Double or single quotes with escape support
            r'Translation\.tr\s*\(\s*`([^`]*(?:\\.[^`]*)*?)`\s*\)',          # Backticks (template strings)
        ]
        
        # Search all .qml and .js files
        file_extensions = ['*.qml', '*.js']
        
        for ext in file_extensions:
            for file_path in self.source_dir.rglob(ext):
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                        
                    for pattern in patterns:
                        matches = re.findall(pattern, content, re.MULTILINE | re.DOTALL)
                        for match in matches:
                            # Handle different match group structures
                            if isinstance(match, tuple):
                                # For improved regex, text is in the second group
                                if len(match) >= 3:
                                    text = match[1]  # Second group is the text content
                                else:
                                    text = match[0] if match else ""
                            else:
                                text = match

                            try:
                                if '\\u' in text or '\\x' in text:
                                    clean_text = bytes(text, "utf-8").decode("unicode_escape")
                                else:
                                    clean_text = (
                                        text.replace('\\n', '\n')
                                            .replace('\\t', '\t')
                                            .replace('\\r', '\r')
                                            .replace('\\"', '"')
                                            .replace('\\\'', "'")
                                            .replace('\\f', '\f')
                                            .replace('\\b', '\b')
                                            .replace('\\\\', '\\')
                                    )
                            except Exception:
                                clean_text = text
                            
                            # Clean text (remove extra whitespace)
                            clean_text = clean_text.strip()
                            if clean_text:
                                translatable_texts.add(clean_text)
                                
                except (UnicodeDecodeError, IOError) as e:
                    print(f"Warning: Cannot read file {file_path}: {e}")
                    
        translatable_texts |= self.extract_extension_texts()
        return translatable_texts
    
    def extension_files(self) -> List[Path]:
        """Files (Nautilus) extensions that look their strings up in these translation files"""
        # The dots tree mirrors the home folder, so in the repo the extensions
        # sit beside the .config that holds the source tree. An installed
        # shell's .config is the home folder's own (or XDG_CONFIG_HOME), and
        # the extensions folder there may hold ones the user added, so only
        # ours is read.
        source_dir = self.source_dir.absolute()
        config_dir = next((p for p in (source_dir, *source_dir.parents)
                           if p.name == '.config'), None)
        if config_dir is not None and config_dir.parent.resolve() != Path.home().resolve():
            return sorted((config_dir.parent / '.local/share/nautilus-python/extensions').glob('*.py'))
        data_home = Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share')
        installed = data_home / 'nautilus-python/extensions/mainstream-share.py'
        return [installed] if installed.is_file() else []

    def extract_extension_texts(self) -> Set[str]:
        """Extract translatable texts from the Files extensions"""
        texts = set()
        for file_path in self.extension_files():
            try:
                tree = ast.parse(file_path.read_text(encoding='utf-8'), filename=str(file_path))
            except (UnicodeDecodeError, IOError, SyntaxError) as e:
                print(f"Warning: Cannot read file {file_path}: {e}")
                continue

            # tr("text") literals, plus the English held in module-level names
            # ending in _TEXT, as a string or as a dict's values, which reach
            # tr() through a variable such as tr(ERROR_TEXT.get(code)).
            nodes = [node.args[0] for node in ast.walk(tree)
                     if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                     and node.func.id == 'tr' and node.args]
            for node in tree.body:
                if isinstance(node, ast.Assign):
                    targets = node.targets
                elif isinstance(node, ast.AnnAssign) and node.value is not None:
                    targets = [node.target]
                else:
                    continue
                if any(isinstance(t, ast.Name) and t.id.endswith('_TEXT') for t in targets):
                    nodes.extend(node.value.values if isinstance(node.value, ast.Dict) else [node.value])

            texts.update(node.value for node in nodes
                         if isinstance(node, ast.Constant) and isinstance(node.value, str)
                         and node.value.strip())
        return texts

    def create_temp_translation_file(self, texts: Set[str]) -> str:
        """Create temporary JSON file containing extracted texts"""
        temp_data = {}
        for text in sorted(texts):
            temp_data[text] = text  # Key and value are the same, indicating untranslated
            
        # Create temporary file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False, encoding='utf-8') as f:
            json.dump(temp_data, f, ensure_ascii=False, indent=2)
            self.temp_extracted_file = f.name
            
        return self.temp_extracted_file
    
    def load_translation_file(self, lang_code: str) -> Dict[str, str]:
        """Load translation file for specified language"""
        file_path = self.translations_dir / f"{lang_code}.json"
        if file_path.exists():
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except (json.JSONDecodeError, IOError) as e:
                print(f"Warning: Cannot load translation file {file_path}: {e}")
                return {}
        return {}
    
    def save_translation_file(self, lang_code: str, translations: Dict[str, str]):
        """Save translation file"""
        file_path = self.translations_dir / f"{lang_code}.json"
        try:
            with open(file_path, 'w', encoding='utf-8') as f:
                json.dump(translations, f, ensure_ascii=False, indent=2)
            print(f"Translation file saved: {file_path}")
        except IOError as e:
            print(f"Error: Cannot save translation file {file_path}: {e}")
    
    def get_available_languages(self) -> List[str]:
        """Get list of available languages"""
        languages = []
        for file_path in self.translations_dir.glob("*.json"):
            lang_code = file_path.stem
            languages.append(lang_code)
        return sorted(languages)
    
    def compare_translations(self, extracted_texts: Set[str], target_lang: str) -> Tuple[Set[str], Set[str]]:
        """Compare extracted texts with existing translation file"""
        existing_translations = self.load_translation_file(target_lang)
        existing_keys = set(existing_translations.keys())
        
        missing_keys = extracted_texts - existing_keys  # Missing keys
        extra_keys = existing_keys - extracted_texts    # Extra keys
        
        return missing_keys, extra_keys
    
    def interactive_update(self, lang_code: str, missing_keys: Set[str], extra_keys: Set[str]):
        """Interactively update translation file, create backup only if updating"""
        translations = self.load_translation_file(lang_code)
        modified = False
        backup_created = False

        # Handle missing keys
        if missing_keys:
            print(f"\nFound {len(missing_keys)} missing translation keys:")
            for i, key in enumerate(sorted(missing_keys), 1):
                print(f"{i}. \"{key}\"")

            if self.ask_yes_no(f"\nAdd these {len(missing_keys)} missing keys?"):
                if not backup_created:
                    backup_file = self.translations_dir / f"{lang_code}.json.bak"
                    with open(backup_file, 'w', encoding='utf-8') as f:
                        json.dump(translations, f, ensure_ascii=False, indent=2)
                    print(f"Created backup: {backup_file}")
                    backup_created = True
                for key in missing_keys:
                    translations[key] = key  # Default value is the key itself
                    modified = True
                print(f"Added {len(missing_keys)} keys")

        # Handle extra keys
        if extra_keys:
            # Only show extra keys that are not marked with /*keep*/
            filtered_extra_keys = [key for key in extra_keys if not (isinstance(translations.get(key, ""), str) and translations.get(key, "").strip().endswith('/*keep*/'))]
            if filtered_extra_keys:
                print(f"\nFound {len(filtered_extra_keys)} extra translation keys:")
                for i, key in enumerate(sorted(filtered_extra_keys), 1):
                    print(f"{i}. \"{key}\" -> \"{translations.get(key, '')}\"")
                if self.ask_yes_no(f"\nDelete these {len(filtered_extra_keys)} extra keys?"):
                    if not backup_created:
                        backup_file = self.translations_dir / f"{lang_code}.json.bak"
                        with open(backup_file, 'w', encoding='utf-8') as f:
                            json.dump(translations, f, ensure_ascii=False, indent=2)
                        print(f"Created backup: {backup_file}")
                        backup_created = True
                    deleted_count = 0
                    for key in filtered_extra_keys:
                        if key in translations:
                            del translations[key]
                            modified = True
                            deleted_count += 1
                    print(f"Deleted {deleted_count} keys")

        # Save changes
        if modified:
            self.save_translation_file(lang_code, translations)
        else:
            print("No changes made")
    
    def ask_yes_no(self, question: str) -> bool:
        """Ask user for confirmation, auto-confirm if yes_mode is True"""
        if getattr(self, "yes_mode", False):
            print(f"{question} (auto-confirmed by --yes)")
            return True
        while True:
            response = input(f"{question} (y/n): ").lower().strip()
            if response in ['y', 'yes']:
                return True
            elif response in ['n', 'no']:
                return False
            else:
                print("Please enter y/yes or n/no")
    
    def cleanup(self):
        """Clean up temporary files"""
        if self.temp_extracted_file and os.path.exists(self.temp_extracted_file):
            os.unlink(self.temp_extracted_file)

def main():
    parser = argparse.ArgumentParser(description="Translation file management tool")
    parser.add_argument("--translations-dir", "-t", 
                       default=".config/quickshell/translations",
                       help="Translation files directory (default: .config/quickshell/translations)")
    parser.add_argument("--source-dir", "-s", 
                       default=".config/quickshell/ii",
                       help="Source code directory (default: .config/quickshell/ii)")
    parser.add_argument("--language", "-l", 
                       help="Specify language code to process (e.g., zh_CN)")
    parser.add_argument("--extract-only", "-e", action="store_true",
                       help="Only extract translatable texts to temporary file")
    parser.add_argument("--show-temp", action="store_true",
                       help="Show temporary extracted file content")
    parser.add_argument("-y", "--yes", action="store_true",
                       help="Skip all confirmation prompts (auto-confirm)")
    parser.add_argument("--check-extensions", action="store_true",
                       help="Only check that the Files extensions' texts are keys in en_US.json (or --language), without writing")
    
    args = parser.parse_args()
    
    # Convert to absolute paths
    translations_dir = os.path.abspath(args.translations_dir)
    source_dir = os.path.abspath(args.source_dir)
    
    print(f"Translation directory: {translations_dir}")
    print(f"Source code directory: {source_dir}")
    
    # Check if directories exist
    if not os.path.exists(source_dir):
        print(f"Error: Source code directory does not exist: {source_dir}")
        sys.exit(1)
    
    # Create manager
    manager = TranslationManager(translations_dir, source_dir, yes_mode=args.yes)
    
    if args.check_extensions:
        # Exits nonzero on a missing key so CI can run it
        lang = args.language or "en_US"
        missing = sorted(manager.extract_extension_texts() - set(manager.load_translation_file(lang)))
        for text in missing:
            print(f"Missing from {lang}.json: \"{text}\"")
        print(f"Checked {len(manager.extension_files())} Files extension file(s), {len(missing)} missing key(s)")
        sys.exit(1 if missing else 0)
    
    try:
        # Extract translatable texts
        print("\nExtracting translatable texts...")
        extracted_texts = manager.extract_translatable_texts()
        print(f"Extracted {len(extracted_texts)} translatable texts")
        
        # Create temporary file
        temp_file = manager.create_temp_translation_file(extracted_texts)
        print(f"Created temporary file: {temp_file}")
        
        if args.show_temp:
            print("\nTemporary file contents:")
            with open(temp_file, 'r', encoding='utf-8') as f:
                print(f.read())
        
        if args.extract_only:
            print("Extract-only mode, program finished")
            return
        
        # Get available languages
        available_languages = manager.get_available_languages()
        
        if args.language:
            target_languages = [args.language]
        else:
            print(f"\nAvailable languages: {', '.join(available_languages) if available_languages else 'None'}")
            if not available_languages:
                if manager.yes_mode:
                    print("No existing translation files found, auto-skipping language creation due to --yes")
                    return
                lang_input = input("Enter language code to create (e.g.: zh_CN): ").strip()
                if lang_input:
                    target_languages = [lang_input]
                else:
                    print("No language specified, program finished")
                    return
            else:
                print("Choose language to process:")
                for i, lang in enumerate(available_languages, 1):
                    print(f"{i}. {lang}")
                print("a. Process all languages")
                if manager.yes_mode:
                    choice = 'a'
                    print("Auto-selecting all languages due to --yes")
                else:
                    choice = input("Please choose (enter number, language code, or 'a'): ").strip()
                
                if choice.lower() == 'a':
                    target_languages = available_languages
                elif choice.isdigit() and 1 <= int(choice) <= len(available_languages):
                    target_languages = [available_languages[int(choice) - 1]]
                elif choice in available_languages:
                    target_languages = [choice]
                else:
                    print("Invalid choice, program finished")
                    return
        
        # Process each language
        for lang in target_languages:
            print(f"\n{'='*50}")
            print(f"Processing language: {lang}")
            print('='*50)
            
            missing_keys, extra_keys = manager.compare_translations(extracted_texts, lang)
            
            if not missing_keys and not extra_keys:
                print(f"Translation file for language {lang} is already up to date")
                continue
            
            print(f"Analysis results:")
            print(f"  Missing keys: {len(missing_keys)}")
            # Load translation file for current lang to get values
            current_translations = manager.load_translation_file(lang)
            filtered_extra_keys = [key for key in extra_keys if not (isinstance(current_translations.get(key, ""), str) and current_translations.get(key, "").strip().endswith('/*keep*/'))]
            ignored_extra_keys = [key for key in extra_keys if (isinstance(current_translations.get(key, ""), str) and current_translations.get(key, "").strip().endswith('/*keep*/'))]
            print(f"  Extra keys: {len(filtered_extra_keys)}")
            if ignored_extra_keys:
                print(f"  Ignored keys: {len(ignored_extra_keys)} (marked with /*keep*/)")
            
            if missing_keys or extra_keys:
                manager.interactive_update(lang, missing_keys, extra_keys)
        
    finally:
        # Clean up temporary files
        manager.cleanup()

if __name__ == "__main__":
    main()
