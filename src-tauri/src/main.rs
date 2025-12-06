/**
 * @license
 * Copyright 2025 a7mddra
 * SPDX-License-Identifier: Apache-2.0
 */

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    // Call the run function from lib.rs
    spatialshot_installer::run();
}