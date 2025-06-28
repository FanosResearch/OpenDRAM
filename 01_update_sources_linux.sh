# -----------------------------------------------------------------------------
# Copyright 2025 McMaster University, University of Waterloo
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# -----------------------------------------------------------------------------

#!/bin/bash

valid_parts=("mt40a256m16ge083e" "mt40a512m8rh075e" "mt40a1g8pm075e")

cs_value=""
part_value=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -cs)
            cs_value="$2"
            shift 2
            ;;
        -part)
            part_value="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if ! [[ "$cs_value" =~ ^[1-5]$ ]]; then
    echo "[error] command scheduler version must be an integer between 1 and 5"
    exit 1
fi

is_valid_part=false
for part in "${valid_parts[@]}"; do
    if [[ "$part" == "$part_value" ]]; then
        is_valid_part=true
        break
    fi
done

if [[ "$is_valid_part" != true ]]; then
    echo "[error] timing constraints not available for the memory part $part_value, please add them manualy."
    echo "[info]  available parts are: mt40a256m16ge083e, mt40a512m8rh075e, mt40a1g8pm075e"
    exit 1
fi

if [[ "$cs_value" == "1" ]]; then
    CS_SOURCE_DIR="./src/submodules_archive/command_scheduler_v1"
elif [[ "$cs_value" == "2" ]]; then
    CS_SOURCE_DIR="./src/submodules_archive/command_scheduler_v2"
elif [[ "$cs_value" == "3" ]]; then
    CS_SOURCE_DIR="./src/submodules_archive/command_scheduler_v3"
elif [[ "$cs_value" == "4" ]]; then
    CS_SOURCE_DIR="./src/submodules_archive/command_scheduler_v4"
elif [[ "$cs_value" == "5" ]]; then
    CS_SOURCE_DIR="./src/submodules_archive/command_scheduler_v5"
fi

if [[ "$part_value" == "mt40a256m16ge083e" ]]; then
    PART_SOURCE_FILE="./src/time_constraints/Micron_MT40A256M16GE_083E.vh"
elif [[ "$part_value" == "mt40a512m8rh075e" ]]; then
    PART_SOURCE_FILE="./src/time_constraints/Micron_MT40A512M8RH_075E.vh"
elif [[ "$part_value" == "mt40a1g8pm075e" ]]; then
    PART_SOURCE_FILE="./src/time_constraints/Micron_MT40A1G8PM_075E.vh"
fi

TARGET_DIR="./src/opendram/command_scheduler"

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

echo "[info] updating command scheduler to version $cs_value..."
cp -r "$CS_SOURCE_DIR/"* "$TARGET_DIR"/

echo "[info] updating timing constraints for the part $part_value..."
cp "$PART_SOURCE_FILE" "$TARGET_DIR/time_constraints.vh"

PREPEND=""
if [[ "$cs_value" == "4" ]]; then
    PREPEND='`define USE_SEPARATE_INTER_INTRA_TABLES\n'
elif [[ "$cs_value" == "5" ]]; then
    PREPEND='`define USE_SEPARATE_INTER_INTRA_TABLES\n'
fi

TMP_FILE=$(mktemp)
{
    echo -e "$PREPEND"
    cat "$TARGET_DIR/time_constraints.vh"
} > "$TMP_FILE"

mv "$TMP_FILE" "$TARGET_DIR/time_constraints.vh"

echo "[info] source files updated successfully."
