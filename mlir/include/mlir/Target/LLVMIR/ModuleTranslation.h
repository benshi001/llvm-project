//===- ModuleTranslation.h - MLIR to LLVM conversion ------------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file implements the translation between an MLIR LLVM dialect module and
// the corresponding LLVMIR module. It only handles core LLVM IR operations.
//
//===----------------------------------------------------------------------===//

#ifndef MLIR_TARGET_LLVMIR_MODULETRANSLATION_H
#define MLIR_TARGET_LLVMIR_MODULETRANSLATION_H

#include "mlir/Dialect/LLVMIR/LLVMInterfaces.h"
#include "mlir/Dialect/OpenMP/OpenMPDialect.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Value.h"
#include "mlir/Support/StateStack.h"
#include "mlir/Target/LLVMIR/Export.h"
#include "mlir/Target/LLVMIR/LLVMTranslationInterface.h"
#include "mlir/Target/LLVMIR/TypeToLLVM.h"

#include "llvm/ADT/SetVector.h"
#include "llvm/IR/FPEnv.h"
#include "llvm/IR/Module.h"

namespace llvm {
class BasicBlock;
class CallBase;
class CanonicalLoopInfo;
class Function;
class IRBuilderBase;
class OpenMPIRBuilder;
class Value;
} // namespace llvm

namespace mlir {
class Attribute;
class Block;
class Location;

namespace LLVM {

namespace detail {
class DebugTranslation;
class LoopAnnotationTranslation;
} // namespace detail

class AliasScopeAttr;
class AliasScopeDomainAttr;
class DINodeAttr;
class LLVMFuncOp;
class ComdatSelectorOp;

/// Implementation class for module translation. Holds a reference to the module
/// being translated, and the mappings between the original and the translated
/// functions, basic blocks and values. It is practically easier to hold these
/// mappings in one class since the conversion of control flow operations
/// needs to look up block and function mappings.
class ModuleTranslation {
  friend std::unique_ptr<llvm::Module>
  mlir::translateModuleToLLVMIR(Operation *, llvm::LLVMContext &, StringRef,
                                bool);

public:
  /// Stores the mapping between a function name and its LLVM IR representation.
  void mapFunction(StringRef name, llvm::Function *func) {
    auto result = functionMapping.try_emplace(name, func);
    (void)result;
    assert(result.second &&
           "attempting to map a function that is already mapped");
  }

  /// Finds an LLVM IR function by its name.
  llvm::Function *lookupFunction(StringRef name) const {
    return functionMapping.lookup(name);
  }

  /// Stores the mapping between an MLIR value and its LLVM IR counterpart.
  void mapValue(Value mlir, llvm::Value *llvm) { mapValue(mlir) = llvm; }

  /// Provides write-once access to store the LLVM IR value corresponding to the
  /// given MLIR value.
  llvm::Value *&mapValue(Value value) {
    llvm::Value *&llvm = valueMapping[value];
    assert(llvm == nullptr &&
           "attempting to map a value that is already mapped");
    return llvm;
  }

  /// Finds an LLVM IR value corresponding to the given MLIR value.
  llvm::Value *lookupValue(Value value) const {
    return valueMapping.lookup(value);
  }

  /// Looks up remapped a list of remapped values.
  SmallVector<llvm::Value *> lookupValues(ValueRange values);

  /// Stores the mapping between an MLIR block and LLVM IR basic block.
  void mapBlock(Block *mlir, llvm::BasicBlock *llvm) {
    auto result = blockMapping.try_emplace(mlir, llvm);
    (void)result;
    assert(result.second && "attempting to map a block that is already mapped");
  }

  /// Finds an LLVM IR basic block that corresponds to the given MLIR block.
  llvm::BasicBlock *lookupBlock(Block *block) const {
    return blockMapping.lookup(block);
  }

  /// Find the LLVM-IR loop that represents an MLIR loop.
  llvm::CanonicalLoopInfo *lookupOMPLoop(omp::NewCliOp mlir) const {
    llvm::CanonicalLoopInfo *result = loopMapping.lookup(mlir);
    assert(result && "attempt to get non-existing loop");
    return result;
  }

  /// Find the LLVM-IR loop that represents an MLIR loop.
  llvm::CanonicalLoopInfo *lookupOMPLoop(Value mlir) const {
    return lookupOMPLoop(mlir.getDefiningOp<omp::NewCliOp>());
  }

  /// Mark an OpenMP loop as having been consumed.
  void invalidateOmpLoop(omp::NewCliOp mlir) { loopMapping.erase(mlir); }

  /// Mark an OpenMP loop as having been consumed.
  void invalidateOmpLoop(Value mlir) {
    invalidateOmpLoop(mlir.getDefiningOp<omp::NewCliOp>());
  }

  /// Map an MLIR OpenMP dialect CanonicalLoopInfo to its lowered LLVM-IR
  /// OpenMPIRBuilder CanonicalLoopInfo
  void mapOmpLoop(omp::NewCliOp mlir, llvm::CanonicalLoopInfo *llvm) {
    assert(llvm && "argument must be non-null");
    llvm::CanonicalLoopInfo *&cur = loopMapping[mlir];
    assert(cur == nullptr && "attempting to map a loop that is already mapped");
    cur = llvm;
  }

  /// Map an MLIR OpenMP dialect CanonicalLoopInfo to its lowered LLVM-IR
  /// OpenMPIRBuilder CanonicalLoopInfo
  void mapOmpLoop(Value mlir, llvm::CanonicalLoopInfo *llvm) {
    mapOmpLoop(mlir.getDefiningOp<omp::NewCliOp>(), llvm);
  }

  /// Stores the mapping between an MLIR operation with successors and a
  /// corresponding LLVM IR instruction.
  void mapBranch(Operation *mlir, llvm::Instruction *llvm) {
    auto result = branchMapping.try_emplace(mlir, llvm);
    (void)result;
    assert(result.second &&
           "attempting to map a branch that is already mapped");
  }

  /// Finds an LLVM IR instruction that corresponds to the given MLIR operation
  /// with successors.
  llvm::Instruction *lookupBranch(Operation *op) const {
    return branchMapping.lookup(op);
  }

  /// Stores a mapping between an MLIR call operation and a corresponding LLVM
  /// call instruction.
  void mapCall(Operation *mlir, llvm::CallInst *llvm) {
    auto result = callMapping.try_emplace(mlir, llvm);
    (void)result;
    assert(result.second && "attempting to map a call that is already mapped");
  }

  /// Finds an LLVM call instruction that corresponds to the given MLIR call
  /// operation.
  llvm::CallInst *lookupCall(Operation *op) const {
    return callMapping.lookup(op);
  }

  /// Maps a blockaddress operation to its corresponding placeholder LLVM
  /// value.
  void mapUnresolvedBlockAddress(BlockAddressOp op, llvm::Value *cst) {
    auto result = unresolvedBlockAddressMapping.try_emplace(op, cst);
    (void)result;
    assert(result.second &&
           "attempting to map a blockaddress operation that is already mapped");
  }

  /// Maps a BlockAddressAttr to its corresponding LLVM basic block.
  void mapBlockAddress(BlockAddressAttr attr, llvm::BasicBlock *block) {
    auto result = blockAddressToLLVMMapping.try_emplace(attr, block);
    (void)result;
    assert(result.second &&
           "attempting to map a blockaddress attribute that is already mapped");
  }

  /// Finds the LLVM basic block that corresponds to the given BlockAddressAttr.
  llvm::BasicBlock *lookupBlockAddress(BlockAddressAttr attr) const {
    return blockAddressToLLVMMapping.lookup(attr);
  }

  /// Removes the mapping for blocks contained in the region and values defined
  /// in these blocks.
  void forgetMapping(Region &region);

  /// Returns the LLVM metadata corresponding to a mlir LLVM dialect alias scope
  /// attribute. Creates the metadata node if it has not been converted before.
  llvm::MDNode *getOrCreateAliasScope(AliasScopeAttr aliasScopeAttr);

  /// Returns the LLVM metadata corresponding to an array of mlir LLVM dialect
  /// alias scope attributes. Creates the metadata nodes if they have not been
  /// converted before.
  llvm::MDNode *
  getOrCreateAliasScopes(ArrayRef<AliasScopeAttr> aliasScopeAttrs);

  // Sets LLVM metadata for memory operations that are in a parallel loop.
  void setAccessGroupsMetadata(AccessGroupOpInterface op,
                               llvm::Instruction *inst);

  // Sets LLVM metadata for memory operations that have alias scope information.
  void setAliasScopeMetadata(AliasAnalysisOpInterface op,
                             llvm::Instruction *inst);

  /// Sets LLVM TBAA metadata for memory operations that have TBAA attributes.
  void setTBAAMetadata(AliasAnalysisOpInterface op, llvm::Instruction *inst);

  /// Sets LLVM dereferenceable metadata for operations that have
  /// dereferenceable attributes.
  void setDereferenceableMetadata(DereferenceableOpInterface op,
                                  llvm::Instruction *inst);

  /// Sets LLVM profiling metadata for operations that have branch weights.
  void setBranchWeightsMetadata(WeightedBranchOpInterface op);

  /// Sets LLVM loop metadata for branch operations that have a loop annotation
  /// attribute.
  void setLoopMetadata(Operation *op, llvm::Instruction *inst);

  /// Sets the disjoint flag attribute for the exported instruction `value`
  /// given the original operation `op`. Asserts if the operation does
  /// not implement the disjoint flag interface, and asserts if the value
  /// is an instruction that implements the disjoint flag.
  void setDisjointFlag(Operation *op, llvm::Value *value);

  /// Converts the type from MLIR LLVM dialect to LLVM.
  llvm::Type *convertType(Type type);

  /// Returns the MLIR context of the module being translated.
  MLIRContext &getContext() { return *mlirModule->getContext(); }

  /// Returns the LLVM context in which the IR is being constructed.
  llvm::LLVMContext &getLLVMContext() const { return llvmModule->getContext(); }

  /// Finds an LLVM IR global value that corresponds to the given MLIR operation
  /// defining a global value.
  llvm::GlobalValue *lookupGlobal(Operation *op) {
    return globalsMapping.lookup(op);
  }

  /// Finds an LLVM IR global value that corresponds to the given MLIR operation
  /// defining a global alias value.
  llvm::GlobalValue *lookupAlias(Operation *op) {
    return aliasesMapping.lookup(op);
  }

  /// Finds an LLVM IR global value that corresponds to the given MLIR operation
  /// defining an IFunc.
  llvm::GlobalValue *lookupIFunc(Operation *op) {
    return ifuncMapping.lookup(op);
  }

  /// Returns the OpenMP IR builder associated with the LLVM IR module being
  /// constructed.
  llvm::OpenMPIRBuilder *getOpenMPBuilder();

  /// Returns the LLVM module in which the IR is being constructed.
  llvm::Module *getLLVMModule() { return llvmModule.get(); }

  /// Translates the given location.
  llvm::DILocation *translateLoc(Location loc, llvm::DILocalScope *scope);

  /// Translates the given LLVM DWARF expression metadata.
  llvm::DIExpression *translateExpression(LLVM::DIExpressionAttr attr);

  /// Translates the given LLVM global variable expression metadata.
  llvm::DIGlobalVariableExpression *
  translateGlobalVariableExpression(LLVM::DIGlobalVariableExpressionAttr attr);

  /// Translates the given LLVM debug info metadata.
  llvm::Metadata *translateDebugInfo(LLVM::DINodeAttr attr);

  /// Translates the given LLVM rounding mode metadata.
  llvm::RoundingMode translateRoundingMode(LLVM::RoundingMode rounding);

  /// Translates the given LLVM FP exception behavior metadata.
  llvm::fp::ExceptionBehavior
  translateFPExceptionBehavior(LLVM::FPExceptionBehavior exceptionBehavior);

  /// Translates the contents of the given block to LLVM IR using this
  /// translator. The LLVM IR basic block corresponding to the given block is
  /// expected to exist in the mapping of this translator. Uses `builder` to
  /// translate the IR, leaving it at the end of the block. If `ignoreArguments`
  /// is set, does not produce PHI nodes for the block arguments. Otherwise, the
  /// PHI nodes are constructed for block arguments but are _not_ connected to
  /// the predecessors that may not exist yet.
  LogicalResult convertBlock(Block &bb, bool ignoreArguments,
                             llvm::IRBuilderBase &builder) {
    return convertBlockImpl(bb, ignoreArguments, builder,
                            /*recordInsertions=*/false);
  }

  /// Converts argument and result attributes from `attrsOp` to LLVM IR
  /// attributes on the `call` instruction. Returns failure if conversion fails.
  /// The `immArgPositions` parameter is only relevant for intrinsics. It
  /// specifies the positions of immediate arguments, which do not have
  /// associated argument attributes in MLIR and should be skipped during
  /// attribute mapping.
  LogicalResult
  convertArgAndResultAttrs(ArgAndResultAttrsOpInterface attrsOp,
                           llvm::CallBase *call,
                           ArrayRef<unsigned> immArgPositions = {});

  /// Gets the named metadata in the LLVM IR module being constructed, creating
  /// it if it does not exist.
  llvm::NamedMDNode *getOrInsertNamedModuleMetadata(StringRef name);

  /// Creates a stack frame of type `T` on ModuleTranslation stack. `T` must
  /// be derived from `StackFrameBase<T>` and constructible from the provided
  /// arguments. Doing this before entering the region of the op being
  /// translated makes the frame available when translating ops within that
  /// region.
  template <typename T, typename... Args>
  void stackPush(Args &&...args) {
    stack.stackPush<T>(std::forward<Args>(args)...);
  }

  /// Pops the last element from the ModuleTranslation stack.
  void stackPop() { stack.stackPop(); }

  /// Calls `callback` for every ModuleTranslation stack frame of type `T`
  /// starting from the top of the stack.
  template <typename T>
  WalkResult stackWalk(llvm::function_ref<WalkResult(T &)> callback) {
    return stack.stackWalk(callback);
  }

  /// RAII object calling stackPush/stackPop on construction/destruction.
  template <typename T>
  using SaveStack = SaveStateStack<T, ModuleTranslation>;

  SymbolTableCollection &symbolTable() { return symbolTableCollection; }

private:
  ModuleTranslation(Operation *module,
                    std::unique_ptr<llvm::Module> llvmModule);
  ~ModuleTranslation();

  /// Converts individual components.
  LogicalResult convertOperation(Operation &op, llvm::IRBuilderBase &builder,
                                 bool recordInsertions = false);
  LogicalResult convertFunctionSignatures();
  LogicalResult convertFunctions();
  LogicalResult convertIFuncs();
  LogicalResult convertComdats();

  LogicalResult convertUnresolvedBlockAddress();

  /// Handle conversion for both globals and global aliases.
  ///
  /// - Create named global variables that correspond to llvm.mlir.global
  /// definitions, similarly Convert llvm.global_ctors and global_dtors ops.
  /// - Create global alias that correspond to llvm.mlir.alias.
  LogicalResult convertGlobalsAndAliases();
  LogicalResult convertOneFunction(LLVMFuncOp func);
  LogicalResult convertBlockImpl(Block &bb, bool ignoreArguments,
                                 llvm::IRBuilderBase &builder,
                                 bool recordInsertions);

  /// Returns the LLVM metadata corresponding to the given mlir LLVM dialect
  /// TBAATagAttr.
  llvm::MDNode *getTBAANode(TBAATagAttr tbaaAttr) const;

  /// Process tbaa LLVM Metadata operations and create LLVM
  /// metadata nodes for them.
  LogicalResult createTBAAMetadata();

  /// Process the ident LLVM Metadata, if it exists.
  LogicalResult createIdentMetadata();

  /// Process the llvm.commandline LLVM Metadata, if it exists.
  LogicalResult createCommandlineMetadata();

  /// Process the llvm.dependent_libraries LLVM Metadata, if it exists.
  LogicalResult createDependentLibrariesMetadata();

  /// Translates dialect attributes attached to the given operation.
  LogicalResult
  convertDialectAttributes(Operation *op,
                           ArrayRef<llvm::Instruction *> instructions);

  /// Translates parameter attributes of a call and adds them to the returned
  /// AttrBuilder. Returns failure if any of the translations failed.
  FailureOr<llvm::AttrBuilder> convertParameterAttrs(mlir::Location loc,
                                                     DictionaryAttr paramAttrs);

  /// Translates parameter attributes of a function and adds them to the
  /// returned AttrBuilder. Returns failure if any of the translations failed.
  FailureOr<llvm::AttrBuilder>
  convertParameterAttrs(LLVMFuncOp func, int argIdx, DictionaryAttr paramAttrs);

  /// Original and translated module.
  Operation *mlirModule;
  std::unique_ptr<llvm::Module> llvmModule;
  /// A converter for translating debug information.
  std::unique_ptr<detail::DebugTranslation> debugTranslation;

  /// A converter for translating loop annotations.
  std::unique_ptr<detail::LoopAnnotationTranslation> loopAnnotationTranslation;

  /// Builder for LLVM IR generation of OpenMP constructs.
  std::unique_ptr<llvm::OpenMPIRBuilder> ompBuilder;

  /// Mappings between llvm.mlir.global definitions and corresponding globals.
  DenseMap<Operation *, llvm::GlobalValue *> globalsMapping;

  /// Mappings between llvm.mlir.alias definitions and corresponding global
  /// aliases.
  DenseMap<Operation *, llvm::GlobalValue *> aliasesMapping;

  /// Mappings between llvm.mlir.ifunc definitions and corresponding global
  /// ifuncs.
  DenseMap<Operation *, llvm::GlobalValue *> ifuncMapping;

  /// A stateful object used to translate types.
  TypeToLLVMIRTranslator typeTranslator;

  /// A dialect interface collection used for dispatching the translation to
  /// specific dialects.
  LLVMTranslationInterface iface;

  /// Mappings between original and translated values, used for lookups.
  llvm::StringMap<llvm::Function *> functionMapping;
  DenseMap<Value, llvm::Value *> valueMapping;
  DenseMap<Block *, llvm::BasicBlock *> blockMapping;

  /// List of not yet consumed MLIR loop handles (represented by an omp.new_cli
  /// operation which creates a value of type CanonicalLoopInfoType) and their
  /// LLVM-IR representation as CanonicalLoopInfo which is managed by the
  /// OpenMPIRBuilder.
  DenseMap<omp::NewCliOp, llvm::CanonicalLoopInfo *> loopMapping;

  /// A mapping between MLIR LLVM dialect terminators and LLVM IR terminators
  /// they are converted to. This allows for connecting PHI nodes to the source
  /// values after all operations are converted.
  DenseMap<Operation *, llvm::Instruction *> branchMapping;

  /// A mapping between MLIR LLVM dialect call operations and LLVM IR call
  /// instructions. This allows for adding branch weights after the operations
  /// have been converted.
  DenseMap<Operation *, llvm::CallInst *> callMapping;

  /// Mapping from an alias scope attribute to its LLVM metadata.
  /// This map is populated lazily.
  DenseMap<AliasScopeAttr, llvm::MDNode *> aliasScopeMetadataMapping;

  /// Mapping from an alias scope domain attribute to its LLVM metadata.
  /// This map is populated lazily.
  DenseMap<AliasScopeDomainAttr, llvm::MDNode *> aliasDomainMetadataMapping;

  /// Mapping from a tbaa attribute to its LLVM metadata.
  /// This map is populated on module entry.
  DenseMap<Attribute, llvm::MDNode *> tbaaMetadataMapping;

  /// Mapping from a comdat selector operation to its LLVM comdat struct.
  /// This map is populated on module entry.
  DenseMap<ComdatSelectorOp, llvm::Comdat *> comdatMapping;

  /// Mapping from llvm.blockaddress operations to their corresponding LLVM
  /// constant placeholders. After all basic blocks are translated, this
  /// mapping is used to replace the placeholders with the LLVM block addresses.
  DenseMap<BlockAddressOp, llvm::Value *> unresolvedBlockAddressMapping;

  /// Mapping from a BlockAddressAttr attribute to it's matching LLVM basic
  /// block.
  DenseMap<BlockAddressAttr, llvm::BasicBlock *> blockAddressToLLVMMapping;

  /// Stack of user-specified state elements, useful when translating operations
  /// with regions.
  StateStack stack;

  /// A cache for the symbol tables constructed during symbols lookup.
  SymbolTableCollection symbolTableCollection;
};

namespace detail {
/// For all blocks in the region that were converted to LLVM IR using the given
/// ModuleTranslation, connect the PHI nodes of the corresponding LLVM IR blocks
/// to the results of preceding blocks.
void connectPHINodes(Region &region, const ModuleTranslation &state);

/// Create an LLVM IR constant of `llvmType` from the MLIR attribute `attr`.
/// This currently supports integer, floating point, splat and dense element
/// attributes and combinations thereof. Also, an array attribute with two
/// elements is supported to represent a complex constant.  In case of error,
/// report it to `loc` and return nullptr.
llvm::Constant *getLLVMConstant(llvm::Type *llvmType, Attribute attr,
                                Location loc,
                                const ModuleTranslation &moduleTranslation);

/// Creates a call to an LLVM IR intrinsic function with the given arguments.
llvm::CallInst *createIntrinsicCall(llvm::IRBuilderBase &builder,
                                    llvm::Intrinsic::ID intrinsic,
                                    ArrayRef<llvm::Value *> args = {},
                                    ArrayRef<llvm::Type *> tys = {});

/// Creates a call to a LLVM IR intrinsic defined by LLVM_IntrOpBase. This
/// resolves the overloads, and maps mixed MLIR value and attribute arguments to
/// LLVM values.
llvm::CallInst *createIntrinsicCall(
    llvm::IRBuilderBase &builder, ModuleTranslation &moduleTranslation,
    Operation *intrOp, llvm::Intrinsic::ID intrinsic, unsigned numResults,
    ArrayRef<unsigned> overloadedResults, ArrayRef<unsigned> overloadedOperands,
    ArrayRef<unsigned> immArgPositions,
    ArrayRef<StringLiteral> immArgAttrNames);

} // namespace detail

} // namespace LLVM
} // namespace mlir

#endif // MLIR_TARGET_LLVMIR_MODULETRANSLATION_H
