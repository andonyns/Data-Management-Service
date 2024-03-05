// SPDX-License-Identifier: Apache-2.0
// Licensed to the Ed-Fi Alliance under one or more agreements.
// The Ed-Fi Alliance licenses this file to you under the Apache License, Version 2.0.
// See the LICENSE and NOTICES files in the project root for more information.

namespace EdFi.DataManagementService.Api.ApiSchema.Model;

/// <summary>
/// A string type branded as a ProjectNamespace, which is the URI path component referring to a ProjectSchema
/// e.g. "ed-fi" for an Ed-Fi data standard version.
/// </summary>
public record struct ProjectNamespace(string Value);