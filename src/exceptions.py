"""可预期的输入、模型和验证错误。"""


class Q1Error(Exception):
    """问题一流程的基类错误。"""


class InputContractError(Q1Error):
    """输入字段、行数、单位或唯一性不满足题目合同。"""


class MissingInputError(InputContractError):
    """缺少题目原始附件。"""


class EnergySpecificationError(Q1Error):
    """题目能耗函数未提供或无法唯一映射。"""


class InfeasibleProblemError(Q1Error):
    """给定数据与模型约束下没有可行方案。"""
