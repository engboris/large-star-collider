type expr_err =
  | EmptyRay
  | NonConstantRayHeader of string
  | InvalidBan of string
  | InvalidRaylist of string
  | InvalidDeclaration of string
  | InvalidMacroArgument of string
  | InvalidBanStructure of string
  | MisplacedStatic of string
  | MisplacedCall of string
  | StaticOnObject
  | StaticOnMacro
  | CircularImport of string
  | FileLoadError of
      { filename : string
      ; message : string
      }
